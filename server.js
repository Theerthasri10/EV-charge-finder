const express = require('express');
const cors = require('cors');
const stationsRouter = require('./routes/stations');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ message: 'EV Charge Finder backend is running' });
});

app.use('/stations', stationsRouter);

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on http://localhost:${PORT}`);
});