module DigitalObject
  DigitalObject = Struct.new(
    "DigitalObject",
    :path,
    :metadata,
    :context,
    keyword_init: true
  )

  ObjectMetadata = Struct.new(
    "ObjectMetadata",
    :id,
    :creator,
    :description,
    :title,
    keyword_init: true
  )
end
