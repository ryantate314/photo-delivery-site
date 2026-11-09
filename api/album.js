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

// Pair full-res and thumbnail keys ignoring extension and case, since thumbnails may be
// re-encoded (e.g. .png -> .jpg) and cameras write upper-case extensions (.JPG).
function thumbnailMatchKey(key) {
  return key
    .replace("thumbnails/", "full-res/")
    .replace(/\.[^./]+$/, "")
    .toLowerCase();
}

async function getPhotos(shoot, token) {

}

async function getAllPhotos(shoot) {
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
      y => thumbnailMatchKey(y.Key) === thumbnailMatchKey(x.Key)
    );
    return {
      fullRes: x.Key,
      thumbnail: thumbnail ? thumbnail.Key : null,
    };
  });

  return {
    id: token,
    shoot: shoot,
    downloadUrl: `${getPhotoUrl(key)}${shoot}.zip`,
    photos: photos.map(x => ({
      thumbnailUrl: getPhotoUrl(x.thumbnail ?? x.fullRes),
      downloadUrl: getPhotoUrl(x.fullRes)
    }))
  };
}

async function getAlbum(shoot, token) {
  const shootTest = /^[a-zA-Z0-9]{1,20}$/;
  // Slugs (e.g. ABC12) or free-form names with spaces; no slashes or dot-only segments.
  const tokenTest = /^(?!\.+$)[a-zA-Z0-9 ._\-]{1,50}$/;

  if (!shootTest.test(shoot) || !tokenTest.test(token))
    throw "Invalid token format.";

  const key = `images/${shoot}/${token}/`;

  const response = await s3Client.send(
    new ListObjectsCommand({
      Bucket: bucketName,
      Prefix: key,
    }),
  );
  // console.debug("S3 response: ", response);

  if (!response.Contents || response.Contents.length == 0) {
    return null;
  }

  const fullResPhotos = response.Contents.filter(
    x => x.Key.startsWith(key + "full-res/") && x.Size > 0
  );

  const thumbnails = response.Contents.filter(
    x => x.Key.startsWith(key + "thumbnails/") && x.Size > 0
  );

  const photos = fullResPhotos.map(x => {
    const thumbnail = thumbnails.find(
      y => thumbnailMatchKey(y.Key) === thumbnailMatchKey(x.Key)
    );
    return {
      fullRes: x.Key,
      thumbnail: thumbnail ? thumbnail.Key : null,
    };
  });

  return {
    id: token,
    shoot: shoot,
    downloadUrl: `${getPhotoUrl(key)}${shoot}.zip`,
    photos: photos.map(x => ({
      thumbnailUrl: getPhotoUrl(x.thumbnail ?? x.fullRes),
      downloadUrl: getPhotoUrl(x.fullRes)
    }))
  };
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
  const albumId = decodePathParam(event.pathParameters.albumId);
  console.debug(`Getting photos for ${shootId}/${albumId}`);
  
  try {

    const album = await getAlbum(shootId, albumId);

    if (!album) {
      console.warn(`Could not find album for ${shootId}/${albumId}`);
      return notFound();
    }

    return ok(album);
  } catch(error) {
    console.error("Error getting album", JSON.stringify(error));
    return formatError(error)
  }
}

function ok(album) {
  var response = {
    "statusCode": 200,
    "headers": {
      "Content-Type": "application/json",
      // Browsers cache for a minute; shared caches (CloudFront) for five.
      "Cache-Control": "public, max-age=60, s-maxage=300",
    },
    "body": JSON.stringify(album),
  }
  return response;
}

function notFound() {
  var response = {
    "statusCode": 404,
    "headers": {
      // Short, so clients pick up an album soon after it's uploaded.
      "Cache-Control": "public, max-age=10",
    },
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