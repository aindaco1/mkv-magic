# Test.19 diagnostics acceptance

Private Universal candidate `0.3.0-test.19`, build `1788785951`. Developer ID-signed;
not notarized or publicly released. Keep the previous app for rollback and do not
disable macOS security protections. Both architectures are included; native Intel
acceptance is still required.

1. Confirm About shows test.19, then repeat the same MP4 + SRT **Verify & Run**
   operation with a distinct output name. Keep the input originals unchanged.
2. If it fails before starting, the error must remain visible. Open **Help >
   Report a Problem…**. Expect a report even if no History job could be created.
3. Use **Export Local Diagnostics…** and send the JSON privately for debugging.
   This export requires neither tool discovery nor a working History store.
4. Optionally inspect a report's exact metadata and choose **Continue in Browser…**.
   Opening the page must not create an issue. Only **Send Reviewed Report** submits.
   The returned GitHub issue link is the delivery confirmation. Retry an uncertain
   result from the same browser page so it retains the same report ID.
5. Cancel a reviewed operation and complete a successful sample operation. Neither
   should appear as a crash. A previous-session unfinished operation is labelled
   interrupted, not proven crashed. A real MKV Magic `.ips` incident can be selected
   explicitly from Console; raw incident contents must not appear in the preview.

The attached older support export cannot establish the exact original failure.
The fixed regression was a swallowed pre-History queue-admission exception, not
proof that every possible Intel source/destination access issue is resolved.
