import sys, re

plugin_file = sys.argv[1]

with open(plugin_file, 'r') as f:
    code = f.read()

changes = 0

# Patch 1: Remove early return after skills-mode agent_end
old = '''api.logger.info("openclaw-mem0: skills-mode agent_end (no auto-capture)");
    });
    return;
  }
  let lastRecallSessionId;'''

new = '''api.logger.info("openclaw-mem0: skills-mode agent_end (no auto-capture)");
    });
    // patched: non-skills handlers also register
  }
  let lastRecallSessionId;'''

if old in code:
    code = code.replace(old, new)
    changes += 1
    print("✓ Patch 1: removed return blocking non-skills handlers")
else:
    print("  Patch 1: not needed (already applied)")

# Patch 2: Bump recall timeout from 8s to 60s
if 'RECALL_TIMEOUT_MS = 8e3' in code:
    code = code.replace('RECALL_TIMEOUT_MS = 8e3', 'RECALL_TIMEOUT_MS = 60e3')
    changes += 1
    print("✓ Patch 2: recall timeout 60s")
else:
    print("  Patch 2: not needed (already applied)")

if changes > 0:
    with open(plugin_file, 'w') as f:
        f.write(code)
    print(f"Applied {changes} patch(es)")
else:
    print("No changes needed")
