--!nonstrict
-- GunAttachments/Types
-- Public type definitions. Purely declarative; returns an empty table at runtime.

-- Slot definition. `order` is also the order in which ApplyStats modifiers run.
export type SlotDef = {
	name: string,
	mountPart: string,
	order: number,
	-- Optional role: "optic" (aim parts, reticle/DOF/LPVO), "grip" (hand IK),
	-- "muzzle" (muzzle point). The first slot with a role answers role queries.
	role: string?,
	overridesMuzzle: boolean?,
}

-- Attachment config: the table returned by an attachment's config ModuleScript
-- (named "Customization" by default). Every field is optional unless stated.
export type AttachmentConfig = {
	IsCompatible: ((weaponName: string) -> boolean)?,
	RootPart: string?,
	MountOffset: CFrame?,
	VisibleParts: { string }?,
	HideGunParts: { string }?,
	HideTransparency: number?,
	TransparentOnADS: { string }?,
	VisibleOnADS: { string }?,
	ApplyStats: ((stats: any) -> any)?,
	-- Callback signatures are frozen for compatibility with existing content:
	OnEquip: ((owner: any, tool: Instance?, node: Instance) -> ())?,
	OnUnequip: ((owner: any, tool: Instance?, node: Instance) -> ())?,
	OnUpdate: ((owner: any, tool: Instance?, deltaTime: number) -> ())?,
	EnableLaser: boolean?,
	EnableFlashlight: boolean?,
	EnableSilencer: boolean?,
	SilencerVolumeMultiplier: number?,
	EnableHandPositioning: boolean?,
	HandGripPart: string?,
	HandToPosition: string?,
	HandTransitionSpeed: number?,
	HandMatchRotation: boolean?,
	overHeating: any?,
	ReticleConfig: any?,
	DepthOfField: any?,
	LPVOZoom: any?,
	[string]: any,
}

-- One active attachment on one gun model.
export type Record = {
	slot: string,
	attachmentName: string,
	config: AttachmentConfig,
	node: Instance,
	model: Instance, -- alias of `node` (legacy field name used by consumers)
	tool: Instance?,
}

-- slot -> attachment name
export type Loadout = { [string]: string }

export type GripData = {
	gripWorldCFrame: CFrame?,
	handToPosition: string,
	transitionSpeed: number,
	matchRotation: boolean,
}

export type Hooks = {
	resolveModel: ((tool: Instance) -> Instance?)?,
	onSnapshotRestored: ((tool: Instance, stats: any) -> ())?,
	isCompatible: ((config: AttachmentConfig, tool: Instance?, slot: string, name: string) -> boolean?)?,
	filterLoadout: ((tool: Instance?, loadout: Loadout) -> Loadout)?,
}

export type Services = {
	heartbeat: any?, -- RBXScriptSignal-like: :Connect(fn(dt)) -> connection with :Disconnect()
	tween: ((instance: Instance, duration: number, delay: number, goals: { [string]: any }) -> ())?,
	http: any?, -- HttpService-like: JSONEncode / JSONDecode
	newInstance: ((className: string) -> Instance)?,
	identityCFrame: any?,
}

export type Options = {
	contentRoot: (Instance | () -> Instance?)?,
	configModuleName: string?,
	slots: { SlotDef }?,
	allowUnknownSlots: boolean?,
	modelRootNames: { string }?,
	nodeSuffix: string?,
	loadout: {
		folderName: string?,
		jsonAttribute: string?,
		maxNameLength: number?,
	}?,
	stats: {
		writeSnapshots: boolean?,
		originalAttribute: string?,
		modifiedAttribute: string?,
	}?,
	hooks: Hooks?,
	services: Services?,
	log: any?,
}

return {}
