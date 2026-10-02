local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNetMax = require(ReplicatedStorage.SPH_Assets.Modules.ThirdParty.ByteNetMax)

return ByteNetMax.defineNamespace("SPH", function()
	return {
		packets = {
			BodyAnimRequest = ByteNetMax.definePacket({
				value = ByteNetMax.cframe,
			}),

			SwitchWeaponRequest = ByteNetMax.definePacket({
				value = ByteNetMax.optional(ByteNetMax.inst),
			}),

			PlayerFire = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					MuzzleCFrame = ByteNetMax.cframe,
					Directions = ByteNetMax.array(ByteNetMax.vec3),
				}),
			}),

			PlaySoundRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					SoundName = ByteNetMax.string,
					FirstPerson = ByteNetMax.bool,
					Suppressed = ByteNetMax.bool,
				}),
			}),

			ReloadRequest = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			PlayerChamberRequest = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			MoveBoltRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Direction = ByteNetMax.cframe,
					MagAmmo = ByteNetMax.uint16,
				}),
			}),

			SwitchFireModeRequest = ByteNetMax.definePacket({
				value = ByteNetMax.uint8,
			}),

			PlayerDropGunRequest = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			PlayerToggleAttachmentRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					AttachmentType = ByteNetMax.uint8,
					Enabled = ByteNetMax.bool,
				}),
			}),

			RepBoltOpenRequest = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			MagGrabRequest = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			ReplicateChamberSmokeRequest = ByteNetMax.definePacket({
				value = ByteNetMax.float32,
			}),

			ReplicateOverheatRequest = ByteNetMax.definePacket({
				value = ByteNetMax.bool,
			}),

			ReplicateLPVORingRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					LeverC0 = ByteNetMax.cframe,
					ArmC0 = ByteNetMax.optional(ByteNetMax.cframe),
					State = ByteNetMax.string,
				}),
			}),

			ReplicateMagEjectRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					GunName = ByteNetMax.string,
					EjectionCFrame = ByteNetMax.cframe,
					DropPartNames = ByteNetMax.array(ByteNetMax.string),
					MagDropFolderSounds = ByteNetMax.auto,
				}),
			}),

			ReplicateGripHandRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					ArmC0 = ByteNetMax.optional(ByteNetMax.cframe),
					ArmName = ByteNetMax.string,
				}),
			}),

			GripHandReplicate = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Character = ByteNetMax.inst,
					ArmC0 = ByteNetMax.optional(ByteNetMax.cframe),
					ArmName = ByteNetMax.string,
				}),
			}),

			PartVisibilityRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					PartName = ByteNetMax.string,
					Visible = ByteNetMax.bool,
				}),
			}),

			ShellEjectRequest = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			PlayerLeanRequest = ByteNetMax.definePacket({
				value = ByteNetMax.int8,
			}),
			
			PlayerFootIKRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Active = ByteNetMax.bool,
					RightOffset = ByteNetMax.float32,
					LeftOffset = ByteNetMax.float32,
					RightNormal = ByteNetMax.vec3,
					LeftNormal = ByteNetMax.vec3,
				}),
			}),

			PlayerAimRequest = ByteNetMax.definePacket({
				value = ByteNetMax.bool,
			}),

			WeaponPushbackRequest = ByteNetMax.definePacket({
				value = ByteNetMax.float32,
			}),

			WeaponPushbackReplicate = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Character = ByteNetMax.inst,
					Pushback = ByteNetMax.float32,
				}),
			}),

			PlayerAimStateRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Aiming = ByteNetMax.bool,
					SightIndex = ByteNetMax.uint8,
				}),
			}),

			AimStateReplicate = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Character = ByteNetMax.inst,
					Aiming = ByteNetMax.bool,
					SightIndex = ByteNetMax.uint8,
				}),
			}),

			PierceGlassRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					GlassPart = ByteNetMax.inst,
					HitPosition = ByteNetMax.vec3,
				}),
			}),

			FallDamageRequest = ByteNetMax.definePacket({
				value = ByteNetMax.float32,
			}),

			BulletHit = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Tool = ByteNetMax.optional(ByteNetMax.inst),
					TurretModel = ByteNetMax.optional(ByteNetMax.inst),
					TurretIndex = ByteNetMax.optional(ByteNetMax.auto),
					RaycastPosition = ByteNetMax.vec3,
					RaycastNormal = ByteNetMax.vec3,
					RaycastInstance = ByteNetMax.inst,
					RaycastMaterial = ByteNetMax.uint16,
					BulletCFrame = ByteNetMax.cframe,
					BloodParams = ByteNetMax.auto,
					IsUBGL = ByteNetMax.bool,
					BulletId = ByteNetMax.uint32,
					HitIndex = ByteNetMax.uint8,
					TravelDistance = ByteNetMax.float32,
				}),
			}),

			PlayerBeginGrenadeThrow = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			PlayerThrowGrenade = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Direction = ByteNetMax.vec3,
					ClientOrigin = ByteNetMax.optional(ByteNetMax.vec3),
					IsLowThrow = ByteNetMax.bool,
				}),
			}),

			RequestGrenadeCosmeticDetach = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					ToolName = ByteNetMax.string,
					GroupId = ByteNetMax.string,
				}),
			}),

			PlayerFireUBGL = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					FirePointCFrame = ByteNetMax.cframe,
					Direction = ByteNetMax.vec3,
				}),
			}),

			UBGLReload = ByteNetMax.definePacket({
				value = ByteNetMax.nothing,
			}),

			FootstepRequest = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					MaterialCode = ByteNetMax.uint16,
					Foot = ByteNetMax.inst,
					Volume = ByteNetMax.float32,
				}),
			}),

			ReplicateMagGrab = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					TargetPlayer = ByteNetMax.inst,
					MagPart = ByteNetMax.inst,
				}),
			}),

			ReplicateBolt = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Player = ByteNetMax.inst,
					Direction = ByteNetMax.cframe,
					MagAmmo = ByteNetMax.uint16,
					Instant = ByteNetMax.bool,
				}),
			}),

			ReplicateFireUBGL = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Player = ByteNetMax.inst,
					FirePointCFrame = ByteNetMax.cframe,
					Direction = ByteNetMax.vec3,
				}),
			}),

			PartVisibilityReplicate = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					TargetCharacter = ByteNetMax.inst,
					PartName = ByteNetMax.string,
					Visible = ByteNetMax.bool,
				}),
			}),

			ToggleAttachmentReplicate = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					LaserPart = ByteNetMax.optional(ByteNetMax.inst),
					Toggle = ByteNetMax.bool,
					OtherCharacter = ByteNetMax.inst,
				}),
			}),

			ShellEjectReplicate = ByteNetMax.definePacket({
				value = ByteNetMax.inst,
			}),

			BodyAnimCommand = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Character = ByteNetMax.inst,
					Angle = ByteNetMax.cframe,
				}),
			}),

			ReplicateFire = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Shooter = ByteNetMax.inst,
					MuzzleCFrame = ByteNetMax.cframe,
					Suppressed = ByteNetMax.bool,
					Directions = ByteNetMax.array(ByteNetMax.vec3),
				}),
			}),

			ReplicateHit = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Tool = ByteNetMax.inst,
					RaycastPosition = ByteNetMax.vec3,
					RaycastNormal = ByteNetMax.vec3,
					RaycastInstance = ByteNetMax.inst,
					RaycastMaterial = ByteNetMax.uint16,
					BloodParams = ByteNetMax.auto,
				}),
			}),

			ReplicateLean = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Character = ByteNetMax.inst,
					LeanDirection = ByteNetMax.int8,
				}),
			}),

			FootstepReplicate = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Player = ByteNetMax.inst,
					MaterialCode = ByteNetMax.uint16,
					Foot = ByteNetMax.inst,
					Volume = ByteNetMax.float32,
				}),
			}),
			
			ReplicateFootIK = ByteNetMax.definePacket({
				value = ByteNetMax.struct({
					Character = ByteNetMax.inst,
					Active = ByteNetMax.bool,
					RightOffset = ByteNetMax.float32,
					LeftOffset = ByteNetMax.float32,
					RightNormal = ByteNetMax.vec3,
					LeftNormal = ByteNetMax.vec3,
				}),
			}),
		},
	}
end)