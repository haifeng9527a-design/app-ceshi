'use strict';
const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, 'serviceAccountKey.json'))) });
const auth = admin.auth();
async function run() {
  let next;
  do {
    const list = await auth.listUsers(1000, next);
    next = list.pageToken;
    for (const u of list.users) await auth.setCustomUserClaims(u.uid, { role: 'authenticated' });
  } while (next);
  console.log('Done');
}
run().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
