import { expect, test } from 'bun:test';

test('fixture is available for the runtime proof', async () => {
  const file = Bun.file('fixtures/approved_replace_text/request.json');
  expect(await file.exists()).toBe(true);
});
