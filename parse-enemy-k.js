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
      const cwM = p.match(/countPerWave:(\d+)/);
      const bossM = p.match(/isBoss:(true|false)/);
      const armM = p.match(/extraArmor:"([^"]*)"/);
      if (!nameM || !dmgM || !hpM || !bossM) continue;
      const baseHp = Math.floor(Number(hpM[1]));
      const obj = {
        name: nameM[1],
        baseDamage: Math.floor(Number(dmgM[1])),
        baseHp: baseHp,
        isBoss: bossM[1] === 'true'
      };
      if (cwM) obj.countPerWave = parseInt(cwM[1], 10);
      if (armM) obj.extraArmor = armM[1];
      arr.push(obj);
    }

    console.log('=== 1) 统计 ===');
    console.log('对象总数:', arr.length);
    const bossCount = arr.filter(x => x.isBoss === true).length;
    const minionCount = arr.filter(x => x.isBoss === false).length;
    console.log('isBoss=true 数量:', bossCount);
    console.log('isBoss=false 数量:', minionCount);

    console.log('\n=== 2) 前15个条目 ===');
    arr.slice(0, 15).forEach((e, i) => {
      const o = { name: e.name, baseDamage: e.baseDamage, baseHp: e.baseHp };
      if (e.countPerWave !== undefined) o.countPerWave = e.countPerWave;
      o.isBoss = e.isBoss;
      if (e.extraArmor) o.extraArmor = e.extraArmor;
      console.log(JSON.stringify(o));
    });

    console.log('\n=== 3) 后15个条目 ===');
    arr.slice(-15).forEach((e, i) => {
      const o = { name: e.name, baseDamage: e.baseDamage, baseHp: e.baseHp };
      if (e.countPerWave !== undefined) o.countPerWave = e.countPerWave;
      o.isBoss = e.isBoss;
      if (e.extraArmor) o.extraArmor = e.extraArmor;
      console.log(JSON.stringify(o));
    });

    const names = arr.map(x => x.name);
    const dupes = names.filter((n, i) => names.indexOf(n) !== i);
    console.log('\n=== 4) 同名单位 ===');
    console.log('同名列表:', dupes.length ? [...new Set(dupes)] : '无');

    const mid = arr.length - 30;
    console.log('\n=== 5) 自洽校验 ===');
    console.log('总数:', arr.length, '= 前15 + 中间', mid, '+ 后15 =', 15 + mid + 15);
    console.log('自洽:', arr.length === 15 + mid + 15 ? '是' : '否');
  });
});
