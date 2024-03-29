module RepositoryData
  RepositoryPackageData = Struct.new(
    "RepositoryPackageData",
    :remote_path,
    :dir_name,
    :metadata,
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
