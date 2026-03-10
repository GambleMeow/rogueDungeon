const https = require('https');
const opts = { hostname: 'www.rouge.wiki', path: '/assets/EnemyCalculatorView-4nGbPcev.js' };
https.get(opts, r => {
  const chunks = [];
  r.on('data', d => chunks.push(d));
  r.on('end', () => {
    const b = Buffer.concat(chunks).toString('utf8');
    const m = b.match(/const K=\[(\{[\s\S]*?\})\];/);
    if (!m) {
      console.log('K not found');
      return;
    }
    let s = m[1].replace(/!0/g, 'true').replace(/!1/g, 'false');
    const arr = [];
    const parts = s.split(/\},\s*\{/);
    for (let i = 0; i < parts.length; i++) {
      let p = i === 0 ? parts[i] + '}' : (i === parts.length - 1 ? '{' + parts[i] : '{' + parts[i] + '}');
      const nameM = p.match(/name:"([^"]*)"/);
      const dmgM = p.match(/baseDamage:(\d+(?:\.\d+)?(?:e\d+)?)/);
      const hpM = p.match(/baseHp:(\d+(?:\.\d+)?(?:e\d+)?)/);
      const bossM = p.match(/isBoss:(true|false)/);
      const armM = p.match(/extraArmor:"([^"]*)"/);
      if (!nameM || !dmgM || !hpM || !bossM) continue;
      const obj = {
        index: arr.length,
        name: nameM[1],
        baseDamage: Math.floor(Number(dmgM[1])),
        baseHp: Math.floor(Number(hpM[1])),
        isBoss: bossM[1] === 'true'
      };
      if (armM) {
        const num = armM[1].match(/\d+/);
        obj.extraArmor = num ? parseInt(num[0], 10) : 0;
      } else {
        obj.extraArmor = 0;
      }
      arr.push(obj);
    }
    const bosses = arr.filter(x => x.isBoss).map(({ index, name, baseHp, baseDamage, extraArmor }) => ({
      index,
      name,
      baseHp,
      baseDamage,
      extraArmor: extraArmor || 0
    }));
    console.log(JSON.stringify(bosses, null, 0));
  });
});
