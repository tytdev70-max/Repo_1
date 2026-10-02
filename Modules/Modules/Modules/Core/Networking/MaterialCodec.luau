local materialByValue = {}
for _, item in ipairs(Enum.Material:GetEnumItems()) do
	materialByValue[item.Value] = item
end

local MaterialCodec = {}

function MaterialCodec.Encode(material: Enum.Material): number
	return material.Value
end

function MaterialCodec.Decode(code: number): Enum.Material
	return materialByValue[code] or Enum.Material.Plastic
end

return MaterialCodec