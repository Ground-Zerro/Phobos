const fs = require('fs');
console.log(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).version);
