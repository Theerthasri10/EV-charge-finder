require('dotenv').config();
const express = require('express');
const cors = require('cors');
const stationsRouter = require('./routes/stations');
const mapsRouter = require('./routes/maps');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '100kb' }));

app.get('/', (req, res) => {
  res.json({ message: 'EV Charge Finder backend is running' });
});

app.use('/stations', stationsRouter);
app.use('/maps', mapsRouter); // Google Maps proxy (key stays on the server)

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
