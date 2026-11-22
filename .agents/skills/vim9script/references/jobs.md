# Jobs and channels

Use a job when an external process would otherwise block the editor. Check `has('job')` and `has('channel')` if the supported builds vary. Keep the process arguments as a list of strings, one argument per item, and set `cwd` in the job options when needed. Shell pipelines, redirections, and glob expansion require an explicit shell or an equivalent implementation. For a child that needs no input, use `in_io: 'null'`. For a pipe that needs EOF after a request, send the data and call `ch_close_in()`.

This example streams stdout to a caller-supplied handler and returns the job to its owner. It intentionally merges stderr into the same stream, appropriate for a human-readable transcript. Keep the streams separate for machine-readable stdout.

```vim
vim9script

export def StartTranscript(argv: list<string>, Put: func(string)): job
  if empty(argv)
    throw 'StartTranscript requires a command'
  endif
  final child = job_start(argv, {
    in_io: 'null',
    out_mode: 'nl',
    err_io: 'out',
    out_cb: (_, line: string) => Put(line),
  })
  if job_status(child) ==# 'fail'
    throw $'Could not start {argv[0]}'
  endif
  return child
enddef
```

Retain the returned `job` in the owning request, buffer state, or module registry. A successful launch says nothing about the command's eventual exit status. Handle a missing executable both as a launch failure and as a possible nonzero child exit on systems where process creation succeeds first.

| Callback | Data and responsibility |
| --- | --- |
| `out_cb`, `err_cb` | In newline mode the callback takes `(ch: channel, line: string)`. Empty lines are data. Raw mode delivers chunks of arbitrary length, so maintain framing state across callbacks. JSON mode requires the matching channel protocol. |
| `exit_cb` | Takes `(child: job, status: number)`. Record status and distinguish success, failure, and requested cancellation. Output may still be buffered. Even a call to `job_status()` can trigger this callback. |
| `close_cb` | Takes `(ch: channel)`. On natural channel closure, Vim delivers pending data callbacks before the close notification. An explicit `ch_close()` does not issue that notification. |

For a result that needs both the complete transcript and the exit code, create per-run state **before** launching. Track a channel-closed flag, an exit-status-received flag, and the status itself. Each completion callback records its fact and calls the same finish function. Finish only when both facts are present, mark the run finished before calling user code, then release its registry entry. Handle launch failure and explicit close directly. This avoids relying on callback order or interpreting status zero as “still waiting.”

Capture stable targets such as a buffer number, window ID, or quickfix list ID at launch. Validate the target and request identity when applying results. A buffer may be wiped or another request may have superseded this one. Mark cancellation before calling `job_stop()` and tolerate late callbacks. Keep UI callbacks short, batch frequent updates, and avoid synchronous channel reads on interactive paths. For request/reply protocols use the channel's matching send API and a response callback, such as `ch_sendexpr()` for Vim's JSON protocol. For debounce, retain the timer ID, stop a superseded timer, and have the callback verify it still owns the request.

Test with a short-lived child that emits a final line and exits. Pump Vim's event loop with short `:sleep` intervals under a bounded deadline in the test driver. Assert captured lines and exit status, and exercise nonzero exit, cancellation, and stale targets when the feature implements them. See the [Vim channel and job manual](https://vimhelp.org/channel.txt.html).
