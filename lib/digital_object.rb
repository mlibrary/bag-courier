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
    :title,
    :creator,
    :description,
    keyword_init: true
  )
end
