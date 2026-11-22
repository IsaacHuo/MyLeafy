import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { authenticationResult, probe, schoolPublicKey, xmlValue } from '../scripts/academic-vpn/probe-auth.mjs';
import { encodeSchoolLogin, seal, unseal } from '../scripts/academic-vpn/probe-school-rpc.mjs';

const { publicKey } = generateKeyPairSync('rsa', { modulusLength: 1024 });
const modulus = Buffer.from(publicKey.export({ format: 'jwk' }).n, 'base64url').toString('hex');
const initial = `<Auth><TwfID>synthetic-session</TwfID><VPNVERSION>M7.6.8R2</VPNVERSION><RndImg>0</RndImg><CSRF_RAND_CODE>synthetic</CSRF_RAND_CODE><RSA_ENCRYPT_KEY>${modulus}</RSA_ENCRYPT_KEY><RSA_ENCRYPT_EXP>65537</RSA_ENCRYPT_EXP></Auth>`;

test('requires explicit authentication success and recognizes additional challenges', () => {
  assert.equal(authenticationResult('<Auth><Result>0</Result></Auth>'), 'vpn_authentication_rejected');
  assert.equal(authenticationResult('<Auth><Result>1</Result><NextAuth>2</NextAuth></Auth>'), 'vpn_sms_required');
  assert.equal(authenticationResult('<Auth><Result>1</Result><NextAuth>7</NextAuth></Auth>'), 'vpn_totp_required');
  assert.equal(authenticationResult('<Auth><Result>1</Result><NextAuth>-1</NextAuth></Auth>'), 'authenticated');
  assert.equal(xmlValue('<Auth><Message><![CDATA[synthetic]]></Message></Auth>', 'Message'), 'synthetic');
  assert.throws(() => schoolPublicKey('<Auth/>'), /vpn_invalid_login_key/);
});

test('submits once, reports only aggregate resources, clears credentials and logs out', async () => {
  const calls = [];
  const credentials = { account: 'synthetic-private-account', password: 'synthetic-private-password' };
  const report = await probe(credentials, async (path, options) => {
    calls.push(path);
    if (path.includes('login_auth')) return initial;
    if (path.includes('login_psw')) {
      assert.equal(new URLSearchParams(options.body).get('svpn_name'), credentials.account);
      assert.ok(!options.body.includes(credentials.password));
      return '<Auth><Result>1</Result><NextAuth>-1</NextAuth></Auth>';
    }
    if (path.includes('rclist')) return '<Rclist><Resource>教务 newjwxt.bjfu.edu.cn synthetic-private-resource</Resource></Rclist>';
    return '<Auth><Result>1</Result></Auth>';
  });
  assert.equal(report.authenticated, true);
  assert.equal(report.includesTimetableHost, true);
  assert.equal(report.cleanup, 'school_confirmed');
  assert.equal(calls.filter(path => path.includes('login_psw')).length, 1);
  assert.ok(calls.at(-1).includes('logout'));
  assert.deepEqual(credentials, { account: '', password: '' });
  assert.ok(!JSON.stringify(report).includes('synthetic-private'));
});

test('password rejection stops without retry or resource access and still logs out', async () => {
  const calls = [];
  const report = await probe({ account: 'synthetic', password: 'synthetic' }, async path => {
    calls.push(path);
    if (path.includes('login_auth')) return initial;
    if (path.includes('login_psw')) return '<Auth><Result>0</Result><ErrorCode>1234</ErrorCode><Message>private content</Message></Auth>';
    return '<Auth><Result>1</Result></Auth>';
  });
  assert.equal(report.result, 'vpn_authentication_rejected');
  assert.equal(report.schoolErrorCode, '1234');
  assert.equal(calls.length, 3);
  assert.ok(!calls.some(path => path.includes('rclist')));
  assert.ok(!JSON.stringify(report).includes('private content'));
});

test('requires user captcha input and does not submit credentials', async () => {
  const calls = [];
  const report = await probe({ account: 'synthetic', password: 'synthetic' }, async path => {
    calls.push(path);
    return path.includes('login_auth') ? initial.replace('<RndImg>0', '<RndImg>1') : '<Auth><Result>1</Result></Auth>';
  });
  assert.equal(report.result, 'vpn_captcha_required');
  assert.ok(!calls.some(path => path.includes('login_psw')));
  assert.ok(calls.at(-1).includes('logout'));
});

test('network failures return a redacted code and attempt session cleanup', async () => {
  const calls = [];
  const report = await probe({ account: 'synthetic', password: 'synthetic' }, async path => {
    calls.push(path);
    if (path.includes('login_auth')) return initial;
    if (path.includes('logout')) return '<Auth><Result>1</Result></Auth>';
    throw new Error('private URL, session, password');
  });
  assert.equal(report.result, 'vpn_probe_failed');
  assert.equal(report.cleanup, 'school_confirmed');
  assert.ok(!JSON.stringify(report).includes('private'));
});

test('probe encoding matches every shared school JavaScript fixture including UTF-16 cases', async () => {
  const fixtures = JSON.parse(await readFile(new URL('../../contracts/jwxt/fixtures/login_encoding.json', import.meta.url), 'utf8'));
  for (const item of fixtures.cases) assert.equal(encodeSchoolLogin(fixtures.key, item.account, item.password), item.encoded);
  assert.throws(() => encodeSchoolLogin('<html>', 'synthetic', 'synthetic'), /school_invalid_key/);
});

test('bridge encrypts private data and rejects a modified authentication tag', () => {
  const keys = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const payload = { account: 'synthetic-private-account', image: 'synthetic-private-image', token: 'synthetic-private-token' };
  const envelope = seal(payload, keys.publicKey);
  assert.ok(!JSON.stringify(envelope).includes('synthetic-private'));
  assert.deepEqual(unseal(envelope, keys.privateKey), payload);
  const tag = Buffer.from(envelope.tag, 'base64'); tag[0] ^= 1;
  assert.throws(() => unseal({ ...envelope, tag: tag.toString('base64') }, keys.privateKey));
});
