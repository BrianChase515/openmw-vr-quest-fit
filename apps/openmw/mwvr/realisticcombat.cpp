#include "realisticcombat.hpp"
#include "openxrinput.hpp"
#include "vrutil.hpp"

#include "../mwbase/environment.hpp"
#include "../mwbase/soundmanager.hpp"

#include "../mwmechanics/weapontype.hpp"
#include "../mwmechanics/npcstats.hpp"

#include "../mwworld/class.hpp"
#include "../mwworld/esmstore.hpp"

#include <components/debug/debuglog.hpp>
#include <components/settings/settings.hpp>
#include <components/vr/trackingmanager.hpp>
#include <components/xr/session.hpp>
#include <components/esm3/loadweap.hpp>
#include <components/esm3/loadsoun.hpp>

namespace MWVR
{
    namespace RealisticCombat
    {

        static const char* stateToString(SwingState state)
        {
            switch (state)
            {
                case SwingState_Cooldown:
                    return "Cooldown";
                case SwingState_Impact:
                    return "Impact";
                case SwingState_Ready:
                    return "Ready";
                case SwingState_Swing:
                    return "Swing";
                case SwingState_Launch:
                    return "Launch";
            }
            return "Error, invalid enum";
        }
        // static const char* swingTypeToString(int type)
        // {
        //     switch (type)
        //     {
        //         case ESM::Weapon::AT_Chop:
        //             return "Chop";
        //         case ESM::Weapon::AT_Slash:
        //             return "Slash";
        //         case ESM::Weapon::AT_Thrust:
        //             return "Thrust";
        //         case -1:
        //             return "Fail";
        //         default:
        //             return "Invalid";
        //     }
        // }

        StateMachine::StateMachine(MWWorld::Ptr ptr, std::string_view space, bool offHand)
            : mPtr(ptr)
            , mMinVelocity(Settings::Manager::getFloat("realistic combat minimum swing velocity", "VR"))
            , mMaxVelocity(Settings::Manager::getFloat("realistic combat maximum swing velocity", "VR"))
            , mSpace(space)
            , mOffHand(offHand)
        {
            Log(Debug::Verbose) << "realistic combat minimum swing velocity: " << mMinVelocity;
            Log(Debug::Verbose) << "realistic combat maximum swing velocity: " << mMaxVelocity;
        }

        // Bare-handed punches only count when the fist is where punches happen: starting no lower
        // than ~chest height and connecting at least 25 cm in front of your face. Running arm pumps
        // swing down by the hips, so they never start a swing or land a hit.
        void StateMachine::updatePunchPose(const osg::Vec3& hand)
        {
            mLaunchPose = mPunchPose = true;
            if (!mHandToHand)
                return;
            auto headSpace = OpenXRInput::instance().getSpace("/default/reference/view");
            if (!headSpace)
                return;
            auto head = headSpace->locate(VR::ReferenceSpace::Local);
            if (!head.status)
                return;
            osg::Vec3 headPos = head.pose.position.asMeters();
            osg::Vec3 fwd = head.pose.orientation * osg::Vec3{ 0, 1, 0 };
            fwd.z() = 0;
            if (fwd.normalize() < 1e-3f)
                return;
            osg::Vec3 d = hand - headPos;
            float reach = d.x() * fwd.x() + d.y() * fwd.y();
            float drop = -d.z();
            mLaunchPose = drop <= 0.55f;
            mPunchPose = reach >= 0.25f && drop <= 0.45f;
        }

        bool StateMachine::canSwing()
        {
            if (mHandToHand && !mLaunchPose && mState == SwingState_Ready)
                return false;
            if (mSwingType >= 0)
                if (mVelocity >= mMinVelocity)
                    if (mSwingType != ESM::Weapon::AT_Thrust || mThrustVelocity >= 0.f)
                        return true;
            return false;
        }

        // Actions common to all transitions
        void StateMachine::transition(SwingState newState, bool resetTime)
        {
            mMaxSwingVelocity = 0.f;
            if (resetTime)
                mTimeSinceEnteredState = 0.f;
            mMovementSinceEnteredState = 0.f;
            mState = newState;
        }

        void StateMachine::reset()
        {
            mMaxSwingVelocity = 0.f;
            mTimeSinceEnteredState = 0.f;
            mVelocity = 0.f;
            mPreviousPosition = osg::Vec3(0.f, 0.f, 0.f);
            mState = SwingState_Ready;
        }

        static bool isMeleeWeapon(int type)
        {
            if (MWMechanics::getWeaponType(type)->mWeaponClass != ESM::WeaponType::Melee)
                return false;
            if (type == ESM::Weapon::HandToHand)
                return true;
            if (type >= 0)
                return true;

            return false;
        }

        static bool isSideSwingValidForWeapon(int type)
        {
            switch (type)
            {
                case ESM::Weapon::HandToHand:
                case ESM::Weapon::BluntOneHand:
                case ESM::Weapon::BluntTwoClose:
                case ESM::Weapon::BluntTwoWide:
                case ESM::Weapon::SpearTwoWide:
                    return true;
                case ESM::Weapon::ShortBladeOneHand:
                case ESM::Weapon::LongBladeOneHand:
                case ESM::Weapon::LongBladeTwoHand:
                case ESM::Weapon::AxeOneHand:
                case ESM::Weapon::AxeTwoHand:
                default:
                    return false;
            }
        }

        void StateMachine::update(float dt, bool enabled)
        {
            // Use the local reference space for swing state management to avoid the player character 
            // moving around the stage interfering with the calculated swing speed.
            auto tp = OpenXRInput::instance().getSpace(mSpace)->locate(VR::ReferenceSpace::Local);
            auto weaponType = MWBase::Environment::get().getWorld()->getActiveWeaponType();

            enabled = enabled && isMeleeWeapon(weaponType);
            mHandToHand = weaponType == ESM::Weapon::HandToHand;
            // The off-hand fist only fights bare-handed (a weapon belongs in the main hand).
            enabled = enabled && (!mOffHand || mHandToHand);
            enabled = enabled && !!tp.status && !!tp.status;

            if (mEnabled != enabled)
            {
                reset();
                mEnabled = enabled;
            }
            if (!enabled)
                return;

            mTimeSinceEnteredState += dt;

            // First determine direction of different swing types

            // Discover orientation of weapon
            osg::Quat weaponDir = tp.pose.orientation;

            // Morrowind animations do not hold weapons at natural angles, so i rotate the hand forward
            // to get a more natural angle on the weapon to allow more comfortable combat.
            if (weaponType != ESM::Weapon::HandToHand)
                weaponDir = osg::Quat(osg::PI_4, osg::Vec3{ 1, 0, 0 }) * weaponDir;

            // Thrust means stabbing in the direction of the weapon
            osg::Vec3 thrustDirection = weaponDir * osg::Vec3{ 0, 1, 0 };

            // Slash and Chop are vertical, relative to the orientation of the weapon (direction of the sharp edge /
            // hammer)
            osg::Vec3 slashChopDirection = weaponDir * osg::Vec3{ 0, 0, 1 };

            // Side direction of the weapon (i.e. The blunt side of the sword)
            osg::Vec3 sideDirection = weaponDir * osg::Vec3{ 1, 0, 0 };

            // Next determine current hand movement

            // If tracking is lost, openxr will return a position of 0
            // So i reset position when tracking is re-acquired to avoid a superspeed strike.
            // Theoretically, the player's hand really could be at 0,0,0
            // but that's a super rare case so whatever.
            if (mPreviousPosition == osg::Vec3(0.f, 0.f, 0.f))
                mPreviousPosition = tp.pose.position.asMeters();

            updatePunchPose(tp.pose.position.asMeters());
            osg::Vec3 movement = tp.pose.position.asMeters() - mPreviousPosition;
            mMovementSinceEnteredState += movement.length();
            mPreviousPosition = tp.pose.position.asMeters();
            osg::Vec3 swingVector = movement / dt;
            osg::Vec3 swingDirection = swingVector;
            swingDirection.normalize();

            // Compute swing velocities

            // Thrust follows the orientation of the weapon. Negative thrust = no attack.
            mThrustVelocity = swingVector * thrustDirection;
            mVelocity = swingVector.length();

            if (isSideSwingValidForWeapon(weaponType))
            {
                // Compute velocity in the plane normal to the thrust direction.
                float thrustComponent = std::abs(mThrustVelocity / mVelocity);
                float planeComponent = std::sqrt(1 - thrustComponent * thrustComponent);
                mSlashChopVelocity = mVelocity * planeComponent;
                mSideVelocity = -1000.f;
            }
            else
            {
                // If side swing is not valid for the weapon, count slash/chop only along in
                // the direction of the weapon's edge.
                mSlashChopVelocity = std::abs(swingVector * slashChopDirection);
                mSideVelocity = std::abs(swingVector * sideDirection);
            }

            float orientationVerticality = std::abs(thrustDirection * osg::Vec3{ 0, 0, 1 });
            float swingVerticality = std::abs(swingDirection * osg::Vec3{ 0, 0, 1 });

            // Pick swing type based on greatest current velocity
            // Note i use abs() of thrust velocity to prevent accidentally triggering
            // chop/slash when player is withdrawing the weapon.
            if (mSideVelocity > std::abs(mThrustVelocity) && mSideVelocity > mSlashChopVelocity)
            {
                // Player is swinging with the "blunt" side of a weapon that
                // cannot be used that way.
                mSwingType = -1;
            }
            else if (std::abs(mThrustVelocity) > mSlashChopVelocity)
            {
                mSwingType = ESM::Weapon::AT_Thrust;
            }
            else
            {
                // First check if the weapon is pointing upwards. In which case slash is not
                // applicable, and the attack must be a chop.
                if (orientationVerticality > 0.707)
                    mSwingType = ESM::Weapon::AT_Chop;
                else
                {
                    // Next check if the swing is more horizontal or vertical. A slash
                    // would be more horizontal.
                    if (swingVerticality > 0.707)
                        mSwingType = ESM::Weapon::AT_Chop;
                    else
                        mSwingType = ESM::Weapon::AT_Slash;
                }
            }

            switch (mState)
            {
                case SwingState_Cooldown:
                    return update_cooldownState();
                case SwingState_Ready:
                    return update_readyState();
                case SwingState_Swing:
                    return update_swingState();
                case SwingState_Impact:
                    return update_impactState();
                case SwingState_Launch:
                    return update_launchState();
                default:
                    throw std::logic_error(
                        std::string("You forgot to implement state ") + stateToString(mState) + " ya dingus");
            }
        }

        void StateMachine::update_cooldownState()
        {
            if (mTimeSinceEnteredState >= mMinimumPeriod)
                transition_cooldownToReady();
        }

        void StateMachine::transition_cooldownToReady()
        {
            transition(SwingState_Ready, true);
        }

        void StateMachine::update_readyState()
        {
            if (canSwing())
                return transition_readyToLaunch();
        }

        void StateMachine::transition_readyToLaunch()
        {
            transition(SwingState_Launch, false);
        }

        void StateMachine::playSwish()
        {
            static ESM::RefId weaponSwish = ESM::RefId::stringRefId("Weapon Swish");
            const ESM::RefId* soundId = &weaponSwish;
            float volume = 0.98f + mStrength * 0.02f;
            float pitch = 0.75f + mStrength * 0.4f;

            const MWWorld::Class& cls = mPtr.getClass();
            if (cls.isNpc() && cls.getNpcStats(mPtr).isWerewolf())
            {
                MWBase::World* world = MWBase::Environment::get().getWorld();
                const MWWorld::ESMStore& store = world->getStore();
                const ESM::Sound* sound = store.get<ESM::Sound>().searchRandom("WolfSwing", world->getPrng());
                if (sound)
                    soundId = &sound->mId;
            }

            if (!soundId->empty())
                MWBase::Environment::get().getSoundManager()->playSound3D(mPtr, *soundId, volume, pitch);
        }

        void StateMachine::update_launchState()
        {
            if (mMovementSinceEnteredState > mMinimumPeriod)
                transition_launchToSwing();
            if (!canSwing())
                return transition_launchToReady();
        }

        void StateMachine::transition_launchToReady()
        {
            transition(SwingState_Ready, false);
        }

        void StateMachine::transition_launchToSwing()
        {
            playSwish();
            transition(SwingState_Swing, true);

            // As a special case, update the new state immediately to allow
            // same-frame impacts.
            update_swingState();
        }

        void StateMachine::update_swingState()
        {
            mMaxSwingVelocity = std::max(mVelocity, mMaxSwingVelocity);
            mStrength = std::min(1.f, (mMaxSwingVelocity - mMinVelocity) / mMaxVelocity);

            // When velocity falls below minimum, transition to register the miss
            if (!canSwing())
                return transition_swingingToImpact(MWWorld::Ptr(), osg::Vec3f(), false);

            if (mHandToHand && !mPunchPose)
                return; // fist isn't out in front yet - keep tracking the swing, no contact

            std::optional<std::pair<MWWorld::Ptr, osg::Vec3f>> victim;
            if (mOffHand)
            {
                // The off hand has no weapon node: aim from the controller itself.
                auto wp = OpenXRInput::instance().getSpace(mSpace)->locateInWorld();
                victim = MWBase::Environment::get().getWorld()->getVRMeleeHitContact(
                    mPtr, wp.pose.position.asMWUnits(), wp.pose.orientation);
            }
            else
                victim = MWBase::Environment::get().getWorld()->getVRMeleeHitContact(mPtr);

            if (victim && victim->first.getClass().isActor())
            {
                auto hit = mPtr.getClass().evaluateHit(mPtr, victim);
                transition_swingingToImpact(hit.mVictim, hit.mHitPosition, hit.mSuccess);
            }
        }

        void StateMachine::transition_swingingToImpact(MWWorld::Ptr victim, osg::Vec3f hitPosition, bool success) 
        {
            mPtr.getClass().hit(mPtr, mStrength, mSwingType, victim, hitPosition, success, true);
            transition(SwingState_Impact, false);
        }

        void StateMachine::update_impactState()
        {
            if (mVelocity < mMinVelocity)
                return transition_impactToCooldown();
        }

        void StateMachine::transition_impactToCooldown()
        {
            transition(SwingState_Cooldown, false);
        }

    }
}
