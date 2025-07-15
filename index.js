import {
  S3Client,
  GetObjectAttributesCommand,
  GetObjectCommand,
} from "@aws-sdk/client-s3";

import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const bucketName = "photos.ryantate314";
const s3Client = new S3Client({});

async function getUrl(shoot, token) {
  const test = /^[a-zA-Z0-9]{1,20}$/;

  if (!test.test(shoot) || !test.test(token))
    throw "Invalid token format.";

  const key = "test.csv";

  // Read the object.
  const response = await s3Client.send(
    new GetObjectAttributesCommand({
      Bucket: bucketName,
      Key: key,
    }),
  );

  console.log("response", JSON.stringify(response));

  const downloadCommand = new GetObjectCommand({
    Bucket: bucketName,
    Key: `${shoot}/${token}`
  })
  const url = await getSignedUrl(s3Client, downloadCommand);

  return url;
}

export const handler = async (event, context) => {
  try {
    const { shoot, token } = context.pathParameters;

    const url = await getUrl(shoot, token);

    if (!url) {
      console.warn(`Could not find download for ${shoot}/${token}`);
      return notFound();
    }

    console.log(`Generated url for ${shoot}/${token}`);

    return redirectToS3(url);
  } catch(error) {
    console.error("Error getting URL", JSON.stringify(error));
    return formatError(error)
  }
}

function redirectToS3(url) {
  var response = {
    "statusCode": 307,
    "headers": {
      "Location": url,
    },
    "isBase64Encoded": false,
  }
  return response
}

function notFound() {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Your Photos Are Being Edited</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: 'Segoe UI', Arial, sans-serif;
      background: #f7f7f9;
      color: #222;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
    }
    .container {
      background: #fff;
      padding: 2rem 2.5rem;
      border-radius: 10px;
      box-shadow: 0 2px 12px rgba(0,0,0,0.07);
      text-align: center;
      max-width: 400px;
    }
    h1 {
      color: #2d6cdf;
      margin-bottom: 1rem;
    }
    p {
      font-size: 1.1rem;
      margin-bottom: 1.5rem;
    }
    .spinner {
      margin: 1.5rem auto 0;
      width: 40px;
      height: 40px;
      border: 4px solid #e0e0e0;
      border-top: 4px solid #2d6cdf;
      border-radius: 50%;
      animation: spin 1s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>Your Photos Aren't Ready Yet</h1>
    <p>
      We're still editing your photos.<br>
      Please check back soon!
    </p>
    <div class="spinner"></div>
  </div>
</body>
</html>`;
  var response = {
    "statusCode": 200,
    "headers": {
      "Content-Type": "text/html",
    },
    "isBase64Encoded": false,
    "body": html,
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