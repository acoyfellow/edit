import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';
import { Type, type Static } from 'typebox';

const requestSchema = Type.Object({
  request: Type.String(),
  approval: Type.String(),
});

type EditInput = Static<typeof requestSchema>;

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: 'edit_propose',
    label: 'Propose bounded edit',
    description: 'Ask for approval, then run a bounded edit through the local Jido and Jev runtime.',
    parameters: Type.Object({ request: Type.String({ description: 'JSON edit request with operations and verification' }) }),
    async execute(_toolCallId, input: { request: string }, _signal, _onUpdate, ctx) {
      if (!ctx.hasUI) {
        return { content: [{ type: 'text', text: 'Human approval is required in interactive mode.' }], details: {}, isError: true };
      }

      const request = JSON.parse(input.request) as Record<string, unknown>;
      const approved = await ctx.ui.confirm('Approve bounded edit?', JSON.stringify(request));
      if (!approved) {
        return { content: [{ type: 'text', text: 'Edit not approved.' }], details: {}, isError: true };
      }

      const approval = { request_digest: digest(request), capabilities: request.capabilities ?? [] };
      const result = await runEdit({ request: JSON.stringify(request), approval: JSON.stringify(approval) }, ctx.cwd);
      return { content: [{ type: 'text', text: JSON.stringify(result) }], details: result, isError: result.status !== 'succeeded' };
    },
  });

  pi.registerTool({
    name: 'edit_run',
    label: 'Run approved edit',
    description: 'Run an approved bounded edit through the local Jido and Jev runtime.',
    parameters: requestSchema,
    async execute(_toolCallId, input: EditInput, _signal, _onUpdate, ctx) {
      const result = await runEdit(input, ctx.cwd);
      return {
        content: [{ type: 'text', text: JSON.stringify(result) }],
        details: result,
        isError: result.status !== 'succeeded',
      };
    },
  });

  const execute = async (args: string, ctx: ExtensionContext) => {
    const [requestPath, approvalPath] = args.trim().split(/\s+/);
    if (!requestPath || !approvalPath) {
      ctx.ui.notify('Usage: /edit <request.json> <approval.json>', 'warning');
      return;
    }

    const result = await runEdit(
      {
        request: await readFile(join(ctx.cwd, requestPath), 'utf8'),
        approval: await readFile(join(ctx.cwd, approvalPath), 'utf8'),
      },
      ctx.cwd,
    );
    ctx.ui.notify(`edit: ${result.status}`, result.status === 'succeeded' ? 'info' : 'error');
  };

  pi.registerCommand('edit', {
    description: 'Run an approved bounded edit. Usage: /edit <request.json> <approval.json>',
    handler: execute,
  });

  pi.on('input', async (event, ctx) => {
    if (!event.text.startsWith('/edit ')) return { action: 'continue' as const };
    await execute(event.text.slice('/edit '.length), ctx);
    return { action: 'handled' as const };
  });
}

function digest(value: Record<string, unknown>): string {
  const canonical = JSON.stringify(Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b))));
  return createHash('sha256').update(canonical).digest('hex');
}

async function runEdit(input: EditInput, cwd: string): Promise<Record<string, unknown>> {
  const runtime = process.env.EDIT_RUNTIME_DIR ?? join(cwd, 'runtime');
  const payload = JSON.stringify({
    request: JSON.parse(input.request),
    approval: JSON.parse(input.approval),
  });

  return await new Promise((resolve) => {
    const child = spawn('mix', ['run', '--no-halt'], {
      cwd: runtime,
      env: {
        PATH: process.env.PATH ?? '',
        HOME: process.env.HOME ?? '',
        MIX_HOME: process.env.MIX_HOME ?? `${process.env.HOME ?? ''}/.mix`,
        HEX_HOME: process.env.HEX_HOME ?? `${process.env.HOME ?? ''}/.hex`,
        TYPESAFE_API_KEY: process.env.TYPESAFE_API_KEY ?? '',
        CLOUDFLARE_API_TOKEN: process.env.CLOUDFLARE_API_TOKEN ?? '',
        CLOUDFLARE_ACCOUNT_ID: process.env.CLOUDFLARE_ACCOUNT_ID ?? '',
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let output = '';
    child.stdout.on('data', (chunk) => {
      output += String(chunk);
      const line = output
        .split('\n')
        .map((value) => value.trim())
        .find((value) => value.startsWith('{'));
      if (line) {
        try {
          resolve(JSON.parse(line));
          child.kill('SIGTERM');
        } catch {
          return;
        }
      }
    });
    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      resolve({ status: 'failed', error: 'runtime timed out' });
    }, 20_000);
    child.on('error', (error) => {
      clearTimeout(timer);
      resolve({ status: 'failed', error: error.message });
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (!output.trim()) resolve({ status: 'failed', error: `runtime exited with ${code}` });
    });
    child.stdin.end(`${payload}\n`);
  });
}
