import {
  S3Client,
  GetObjectAttributesCommand,
  GetObjectCommand,
  ListObjectsCommand,
} from "@aws-sdk/client-s3";

const bucketName = "photos.ryantate314.net";
const s3Client = new S3Client({});
const sitePrefix = "https://photos.ryantate314.net";

function getPhotoUrl(key) {
  return `${sitePrefix}/${key}`;
}

async function getAlbums(shoot) {
  const key = `images/${shoot}/`;

  const response = await s3Client.send(
    new ListObjectsCommand({
      Bucket: bucketName,
      Prefix: key,
    }),
  );

  if (!response.Contents || response.Contents.length == 0) {
    return null;
  }

  const fullResPhotos = response.Contents.filter(
    x => x.Key.includes("full-res/") && x.Size > 0
  );

  const thumbnails = response.Contents.filter(
    x => x.Key.includes("thumbnails/") && x.Size > 0
  );

  const photos = fullResPhotos.map(x => {
    const thumbnail = thumbnails.find(
      y => y.Key.replace("thumbnails/", "full-res/") == x.Key
    );
    return {
      fullRes: x.Key,
      thumbnail: thumbnail ? thumbnail.Key : null,
    };
  });

  const albums = photos.reduce((acc, cur) => {
    const album = cur.fullRes.split("/")[2];
    if (!acc[album]) {
      acc[album] = [];
    }
    acc[album].push(cur);
    return acc;
  }, {});

  return Object.keys(albums).map(token => ({
    id: token,
    shoot: shoot,
    downloadUrl: `${getPhotoUrl(key)}${shoot}.zip`,
    photos: albums[token].map(x => ({
      thumbnailUrl: getPhotoUrl(x.thumbnail),
      downloadUrl: getPhotoUrl(x.fullRes)
    }))
  }));
}

function decodePathParam(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

export const handler = async (event, context) => {
  const shootId = decodePathParam(event.pathParameters.shootId);
  console.debug(`Getting photos for ${shootId}`);
  
  // try {

    const albums = await getAlbums(shootId);

    if (!albums || albums.length == 0) {
      console.warn(`Could not find albums for ${shootId}`);
      return notFound();
    }

    return ok(albums);
  // } catch(error) {
  //   console.error("Error getting albums", JSON.stringify(error));
  //   return formatError(error)
  // }
}

function ok(album) {
  var response = {
    "statusCode": 200,
    "headers": {
      "Content-Type": "application/json",
    },
    "body": JSON.stringify(album),
  }
  return response;
}

function notFound() {
  var response = {
    "statusCode": 404,
  }
  return response;
}

function formatError(error) {
  return {
    statusCode: 500,
    headers: {
      "Content-Type": "text/plain",
    },
    body: "An unexpected error occurred.",
  };
}