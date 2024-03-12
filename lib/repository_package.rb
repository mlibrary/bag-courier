module RepositoryPackage
  RepositoryPackage = Struct.new(
    "RepositoryPackage",
    :remote_path,
    :metadata,
    :context,
    :stored_time,
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
