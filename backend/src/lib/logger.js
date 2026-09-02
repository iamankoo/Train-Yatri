// Deliberately tiny - no logging library dependency. Structured JSON
// lines to stdout (what Render and every other host captures), with
// one hard rule: never pass anything containing the RailRadar API key
// or an Authorization header value through this. Callers pass plain
// field objects (request timing, normalized status, error category,
// cache hit/miss, HTTP status - see Block 6 Part 47) - never raw
// upstream headers or raw error bodies that might carry the key back
// in an error message.

function write(level, event, fields = {}) {
  const line = {
    level,
    event,
    time: new Date().toISOString(),
    ...fields,
  };
  const serialized = JSON.stringify(line);
  if (level === 'error') {
    console.error(serialized);
  } else {
    console.log(serialized);
  }
}

export const logger = {
  info: (event, fields) => write('info', event, fields),
  warn: (event, fields) => write('warn', event, fields),
  error: (event, fields) => write('error', event, fields),
};
