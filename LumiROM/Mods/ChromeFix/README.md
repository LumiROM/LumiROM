# ChromeFix

Ships `/system/lib64/libzygote.dylib.so` for `zygote_next` (the Rust zygote of
One UI 9 / Android 17) with one instruction patched.

## Why

`FileDescriptorRegistry::reset_for_subspecies()` calls `audit()` after
`register_new()` when an AppZygote subspecies is spawned. `register_new()`
decides whether an fd is already tracked with `is_registered()`, which compares
fd numbers only and never checks the entry's `closed()` flag. The
`info!("Resetting FileDescriptorRegistry…")` line above reopens liblog on the fd
numbers that `execute_actions()` just closed, so those new descriptors match
stale closed entries, are skipped, and are never adopted. `audit()` then sees
open descriptors without a live registry entry and returns
`FileDescriptorUnexpected`.

The caller throws that error away (`map_err(|_| ClientError::Reinitialization)`),
the child zygote keeps serving on the epoll fd that `execute_actions()` already
closed, `epoll_wait()` returns `EBADF`, the child exits without ever binding
`@com.android.internal.os.AppZygoteInit/<uuid>`, and `system_server` waits 30 s
for it until the watchdog kills it. Visible symptom: any app with
`android:useAppZygote` freezes the phone for ~30 s and soft-reboots it.

## The patch

One AArch64 instruction in
`FileDescriptorRegistry::reset_for_subspecies` (`@ 0x27dd4`):

```
0x27eb0:  94006280  bl  audit   ->   1400000b  b  0x27edc
```

`0x27edc` is the function's `Ok(())` path (`str x22, [x19]` + epilogue), so
`reset_for_subspecies()` returns `Ok` right after `register_new()`.

What is kept:

- `execute_actions(ForkType::Subspecies)` — closes the parent's client sockets,
  the old epoll fd and the stale log fds.
- `register_new()` — still rejects unknown descriptors and propagates its own
  errors (the check at `0x27ea4` is untouched).
- `audit()` in `Server::new()` — not patched.

Only the registry-vs-reality comparison that misfires is skipped. `audit()` has
no side effects, so dropping it cannot corrupt state. This is a workaround, not
the upstream fix: `is_registered()` should ignore closed entries, and
`register_new()` should replace them instead of pushing a duplicate.

## Hashes

| File | sha256 |
|---|---|
| `libzygote.dylib.so` in this mod (patched) | `4887b2096005c3e01b471922c1777d0fd1f06c70f58476c51537bd7b61450d9e` |
| Stock A34 library | `f7c7c35fb02ad3aee4bd99f6abb6aad8cfde63409b620063e8bdf23621914788` |

Only 4 bytes differ between the two. Size: 305336 bytes.

## Notes

- Verified on LumiROM 9.0.2 (`A346BXXUHGZJ8`): the patched library reproduces
  byte-for-byte the binary used by the reporter to test the fix, and the
  AppZygote starts, binds its abstract socket and spawns sandboxed renderers.
- Offset-specific. If the base firmware changes, re-derive the site from the
  `reset_for_subspecies` symbol and the `audit` PLT stub before reusing it.
- The mod id stays `chromefix` so existing build references keep working.
