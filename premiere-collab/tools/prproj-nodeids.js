// Prints the nodeId of each timeline clip in a .prproj file, as Premiere
// would report it at load (TIMELINE-PROBES.md section 1: nodeId is the
// <TrackItem><Node><ID> value, shown in hex). Use it to predict what the
// guest laptop will see without opening Premiere.
//
// Usage: node prproj-nodeids.js <path-to.prproj>
const fs = require('fs');
const zlib = require('zlib');

const file = process.argv[2];
if (!file) {
  console.error('Usage: node prproj-nodeids.js <path-to.prproj>');
  process.exit(1);
}

const xml = zlib.gunzipSync(fs.readFileSync(file)).toString('utf8');

// Index every element that has an ObjectID or ObjectUID, so refs can be followed.
const byId = new Map();
const objRe = /<(\w+)\s[^>]*?Object(U?ID)="([^"]+)"[^>]*>([\s\S]*?)<\/\1>/g;
let m;
while ((m = objRe.exec(xml))) byId.set(m[3], { tag: m[1], body: m[4] });

const hex = (n) => Number(n).toString(16).padStart(8, '0');
const ref = (body, tag) => {
  const r = new RegExp(`<${tag}[^>]*Object(?:U)?Ref="([^"]+)"`).exec(body);
  return r ? r[1] : null;
};
const all = (body, re) => [...body.matchAll(re)].map((x) => x[1]);

// Sequences -> TrackGroups -> Tracks -> ClipItems -> TrackItem node ID.
for (const [, seq] of [...byId].filter(([, o]) => o.tag === 'Sequence')) {
  const name = (/<Name>([^<]*)<\/Name>/.exec(seq.body) || [])[1] || '(unnamed)';
  console.log(`Sequence: ${name}`);
  for (const tgRef of all(seq.body, /<TrackGroup[^>]*>[\s\S]*?<Second ObjectRef="([^"]+)"/g)) {
    const tg = byId.get(tgRef);
    if (!tg) continue;
    const kind = tg.tag.replace('TrackGroup', '') || tg.tag;
    all(tg.body, /<Track Index="\d+" ObjectURef="([^"]+)"/g).forEach((tRef, ti) => {
      const track = byId.get(tRef);
      if (!track) return;
      const clips = all(track.body, /<TrackItem Index="\d+" ObjectRef="([^"]+)"/g);
      clips.forEach((cRef, ci) => {
        const clip = byId.get(cRef);
        if (!clip) return;
        const id = (/<Node[^>]*>[\s\S]*?<ID>(\d+)<\/ID>/.exec(clip.body) || [])[1];
        const start = (/<Start>(\d+)<\/Start>/.exec(clip.body) || [])[1];
        console.log(`  ${kind} track ${ti + 1} clip ${ci}: ${id ? `nodeId=${hex(id)} (ID ${id})` : 'nodeId=none stored (Premiere assigns at load)'} start=${start}`);
      });
    });
  }
}
