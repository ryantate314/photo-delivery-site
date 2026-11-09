const express = require('express');
const cors = require('cors');
const app = express();

const port = 3141;

app.use(cors());

app.get('/api/shoots/:shootId/albums', (req, res) => {
  const photos = Array.from({ length: 12 }, (_, i) => ({
    downloadUrl: `https://example.com/photo${i}.jpg`,
    thumbnailUrl: `https://placehold.co/96?text=${i + 1}`,
  }));
  res.send(JSON.stringify(['ABC12', 'Alissa and Missy'].map(id => ({
    id,
    shootId: req.params.shootId,
    downloadUrl: 'https://example.com/download.zip',
    photos,
  }))));
});

app.get('/api/shoots/:shootId/albums/:albumId', (req, res) => {
  res.send(JSON.stringify(null));
  return;
  const testData = {
    id: req.params.albumId,
    shootId: req.params.shootId,
    downloadUrl: 'https://example.com/download.zip',
    photos: [
      {
        downloadUrl: 'https://example.com/photo1.jpg',
        thumbnailUrl: 'https://example.com/thumbnail1.jpg',
      }
    ]
  };
  res.send(JSON.stringify(testData));
});

app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});
