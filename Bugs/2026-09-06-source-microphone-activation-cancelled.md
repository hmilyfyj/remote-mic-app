# Voice activation cancelled after source microphone switching

## Reproduction and Evidence

- Branch: `feature/448-source-microphone`, faulty revision `4899ad1`.
- macOS 26.3.1 (a), build 25D771280a, Apple Silicon, MiRemoteV 2ch.
- User enabled source switching and pressed the RC003 voice key. Sessions 1-13 at
  2026-09-06 05:11-05:12 UTC switched input and submitted Fn, then terminated with
  `reason=audio_interrupted`; most cancellations followed Fn within 3-6 ms.
- A local AVAudioEngine experiment reproduced an explicit output binding being lost
  after changing the default input. The existing recovery repeatedly reconstructed
  engines that immediately stopped. Raw AudioUnit and AUAudioUnit device setters
  showed the same behavior. No third-party application files were inspected.

## Cause and Change

The controller treated default-input property confirmation as readiness to start
the tool. Core Audio subsequently changed the engine's route asynchronously.
The active-session health check then released Fn and closed the remote stream.

The controller now waits for output readiness before submitting Fn, buffering
incoming PCM throughout. The output reuses the engine and resets the player only
when its delivery queue is empty, then rebinds and restarts as needed. The binding
must remain healthy for 150 ms, with a 1 s total limit. Input restoration also
waits for output readiness. Pending generic recovery is cancelled when a managed
session takes ownership; hardware notifications defer to the managed lifecycle.

The first integration experiment found that restarting the engine alone retained
the player's old timeline: enqueue succeeded but playback never drained, even
after 3 s. Stopping the empty player before engine restart fixed that failure.
Normal pending voice audio is still drained before stopping or restoring input.
Startup verification also reproduced the generic idle recovery loop. Reconfiguring
the same unhealthy output now reuses the empty engine/player through the same
restart path. A separate opt-in integration case verifies idle recovery stability.

## Validation

- Full local-only suite: 525 tests reported, with both opt-in hardware tests skipped
  in the default run and separately passed below.
- `REMOTE_MIC_LOCAL_ONLY=1 swift test --filter SourceMicrophoneSessionTests`:
  29 tests passed, including route-wait buffering, failed readiness, stale callbacks,
  and early remote release.
- `REMOTE_MIC_LOCAL_ONLY=1 REMOTE_MIC_TEST_AUDIO_ROUTE=1 swift test --filter SourceMicrophoneRouteIntegrationTests`:
  both tests passed in 26.333 s, including idle recovery. Ten round trips changed
  real system input 20 times. Each
  transition retained the selected virtual output through a delayed check and
  delivered 1,600 silent samples via `.dataPlayedBack`, with zero pending or
  interrupted samples. Original input restored at completion.
- The opt-in integration test uses silence and public Core Audio interfaces. It
  does not submit Fn, collect microphone audio, or inspect third-party state.
- Real RC003 speech, target-tool activation, first/last word completeness, physical
  keyboard alternation, and separate built-in/USB scenarios remain user acceptance
  work. Added route settling introduces measurable activation latency.
