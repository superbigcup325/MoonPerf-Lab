///|
fn join(directory : String, name : String) -> String {
  if directory.has_suffix("/") {
    directory + name
  } else {
    directory + "/" + name
  }
}

///|
async fn temp_dir() -> String {
  @fs.tmpdir(prefix="mpf-host-") catch {
    _ => abort("cannot create temporary directory")
  }
}

///|
async test "captures exit code and stdout" {
  let directory = temp_dir()
  let stdout_path = join(directory, "stdout.txt")
  let stderr_path = join(directory, "stderr.txt")
  let result = @host.run(
    "sh",
    ["-c", "echo hello; exit 3"],
    None,
    1000,
    stdout_path,
    stderr_path,
  ) catch {
    _ => abort("host run failed")
  }
  inspect(result.exit_code, content="3")
  inspect(result.timed_out, content="false")
  let text = @fs.read_file(stdout_path).text() catch {
    _ => abort("cannot read stdout")
  }
  inspect(text, content="hello\n")
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}

///|
async test "timeout kills the process group" {
  let directory = temp_dir()
  let stdout_path = join(directory, "stdout.txt")
  let stderr_path = join(directory, "stderr.txt")
  let child_pid_path = join(directory, "child.pid")
  let command = "sleep 5 & echo $! > " + child_pid_path + "; wait"
  let result = @host.run(
    "sh",
    ["-c", command],
    None,
    200,
    stdout_path,
    stderr_path,
  ) catch {
    _ => abort("host run failed")
  }
  inspect(result.timed_out, content="true")
  let pid_text = @fs.read_file(child_pid_path).text() catch {
    _ => abort("cannot read child pid")
  }
  @async.sleep(100)
  inspect(
    @fs.exists("/proc/" + pid_text.trim().to_owned()) catch {
      _ => false
    },
    content="false",
  )
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}
