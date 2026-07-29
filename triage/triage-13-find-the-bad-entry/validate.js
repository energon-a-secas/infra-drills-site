// Service registry validator.
//
// Reads a JSON array of services and checks each against the registry rules.
// On any violation it exits 1 with a single vague message and NO location —
// this is deliberately unhelpful, and it is why you bisect the file instead of
// reading it top to bottom.
//
// Rules per service:
//   - name:   non-empty string
//   - port:   integer in the range 1..65535
//   - weight: number in the range 0..100
//
// Because the validator accepts any array, you can split services.json into
// halves, validate each half, and follow the failing half down to one entry.

const fs = require("fs");

const path = process.argv[2];
if (!path) {
  console.error("usage: node validate.js <services.json>");
  process.exit(2);
}

let services;
try {
  services = JSON.parse(fs.readFileSync(path, "utf8"));
} catch (e) {
  console.error("ERROR: services file is not valid JSON");
  process.exit(2);
}

if (!Array.isArray(services)) {
  console.error("ERROR: service registry must be a JSON array");
  process.exit(2);
}

function isValid(s) {
  if (typeof s !== "object" || s === null) return false;
  if (typeof s.name !== "string" || s.name.length === 0) return false;
  if (!Number.isInteger(s.port) || s.port < 1 || s.port > 65535) return false;
  if (typeof s.weight !== "number" || s.weight < 0 || s.weight > 100) return false;
  return true;
}

const allValid = services.every(isValid);

if (!allValid) {
  console.error("ERROR: service registry failed validation");
  process.exit(1);
}

console.log(`OK: ${services.length} services valid`);
