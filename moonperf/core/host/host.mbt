///|
pub suberror HostError {
  Message(String)
}

///|
pub struct CommandResult {
  exit_code : Int32
  timed_out : Bool
  wall_us : Double
  stdout_path : String
  stderr_path : String
}

///|
fn with_setsid(command : String, args : Array[String]) -> Array[String] {
  let full_args : Array[String] = ["-w", command]
  for arg in args {
    full_args.push(arg)
  }
  full_args
}

///|
/// Run one child in a new session/process group, with a hard timeout.
///
/// On Linux the child is started through `setsid -w`; a timeout kills the
/// whole group with `kill -KILL -<pid>` and reaps the child. The caller gets
/// only raw facts: exit code, timed-out flag, wall microseconds and the paths
/// of the captured stdout/stderr files.
pub async fn run(
  command : String,
  args : Array[String],
  cwd : String?,
  timeout_ms : Int32,
  stdout_path : String,
  stderr_path : String,
) -> CommandResult raise HostError {
  let full_args = with_setsid(command, args)
  let stdout = @process.redirect_to_file(stdout_path) catch {
    _ => raise HostError::Message("cannot redirect stdout to " + stdout_path)
  }
  let stderr = @process.redirect_to_file(stderr_path) catch {
    _ => raise HostError::Message("cannot redirect stderr to " + stderr_path)
  }
  let pid = try {
    if cwd is Some(directory) {
      @process.spawn_orphan(
        "setsid",
        full_args,
        stdout~,
        stderr~,
        cwd=directory,
      )
    } else {
      @process.spawn_orphan("setsid", full_args, stdout~, stderr~)
    }
  } catch {
    error =>
      raise HostError::Message("cannot spawn child: " + error.to_string())
  }
  stdout.close()
  stderr.close()

  let started = @bench.monotonic_clock_start()
  let waited = @async.with_timeout_opt(timeout_ms, () => @process.wait_pid(pid)) catch {
    error =>
      raise HostError::Message("cannot wait for child: " + error.to_string())
  }
  let wall_us = @bench.monotonic_clock_end(started)
  match waited {
    Some(exit_code) =>
      { exit_code, timed_out: false, wall_us, stdout_path, stderr_path, }
    None => {
      let _ = @process.run("kill", ["-KILL", "-" + pid.to_string()]) catch {
        _ => 0
      }
      let _ = @async.with_timeout_opt(1000, () => @process.wait_pid(pid)) catch {
        _ => None
      }
      { exit_code: -1, timed_out: true, wall_us, stdout_path, stderr_path, }
    }
  }
}
