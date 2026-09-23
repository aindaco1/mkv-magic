# ADR 0003: Reviewed native reporting without main-app networking

- Status: Accepted
- Date: 2026-09-07

The user approved direct in-app support submission to remove the redundant
browser review. Review remains explicit: Send Reviewed Report submits only the
displayed bounded metadata, not raw logs, media, filenames, or credentials.

The main app retains its no-network sandbox. A Universal, separately sandboxed
XPC service has only sandbox and network-client entitlements, no selected-file,
bookmark, or inheritance entitlement. The app requires the packaged helper's
designated signature; the helper requires the fixed production app identifier
and its own Apple-anchored signing team on the actual XPC peer. It does not need
access to the parent app's files. Ad-hoc helpers cannot submit reports. Its only submission interface
accepts a revalidated report, never a URL or HTTP headers. The transport fixes the
HTTPS relay endpoint, rejects redirects, disables cookies/credential storage and
caching, and bounds request/response sizes and timeouts. Public GitHub credentials
remain server-side. Existing relay validation, grouping, and same-ID receipts are
reused unchanged. No browser is opened unless the user chooses View GitHub Issue.

The manual system-crash import control is removed. Prior-session interrupted
operations remain reportable and are not misrepresented as proven crashes. The
existing crash projection remains readable for compatibility, without automatic
scanning of system crash folders or expanded filesystem permissions.

All file outputs and exports use the shared destination chooser. A configured
folder applies to every output. Beside-source uses the relevant source folder;
source-less exports remember a separate export folder. Only Ask Every Time shows
a save panel. Missing folder authority requires an explicit folder grant, retained
as a bounded bookmark cache for future saves. Automatic names never overwrite an
existing file. Permission, verified-output, and original-preservation failures
remain fail closed.
