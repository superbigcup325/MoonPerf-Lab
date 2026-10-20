///|
let sample_output : String =
  #|{"n": 16, "sum": 1.5, "count_above": 5, "note": "extra"}

///|
async test "reads declared scalar fields and ignores extras" {
  let directory = @fs.tmpdir(prefix="mpf-verify-") catch {
    _ => abort("cannot create temporary directory")
  }
  let path = directory + "/output.json"
  @fs.write_file(path, sample_output) catch {
    _ => abort("cannot write output")
  }
  let (values, errors) = @verify.read_output(path, ["n", "sum", "count_above"]) catch {
    _ => abort("read_output raised")
  }
  inspect(errors.length(), content="0")
  inspect(values.get("n").unwrap().stringify(), content="16")
  inspect(values.get("sum").unwrap().stringify(), content="1.5")
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}

///|
test "exact mode compares JSON types and values" {
  let subject : Map[String, Json] = Map([
    ("n", Json::number(16.0)),
    ("sum", Json::number(1.5)),
  ])
  let reference : Map[String, Json] = Map([
    ("n", Json::number(16.0)),
    ("sum", Json::number(1.5)),
  ])
  inspect(
    @verify.compare_values(subject, reference, ["n", "sum"], "exact", 0.0, 0.0).length(),
    content="0",
  )
  let wrong : Map[String, Json] = Map([
    ("n", Json::number(15.0)),
    ("sum", Json::number(1.5)),
  ])
  inspect(
    @verify.compare_values(wrong, reference, ["n", "sum"], "exact", 0.0, 0.0).length(),
    content="1",
  )
}

///|
test "tolerance mode accepts a rounding difference" {
  let subject : Map[String, Json] = Map([("sum", Json::number(1.0000001))])
  let reference : Map[String, Json] = Map([("sum", Json::number(1.0))])
  inspect(
    @verify.compare_values(
      subject,
      reference,
      ["sum"],
      "tolerance",
      1.0e-6,
      0.0,
    ).length(),
    content="0",
  )
  let too_far : Map[String, Json] = Map([("sum", Json::number(1.01))])
  inspect(
    @verify.compare_values(
      too_far,
      reference,
      ["sum"],
      "tolerance",
      1.0e-6,
      0.0,
    ).length(),
    content="1",
  )
}

///|
test "type mismatch is rejected" {
  let subject : Map[String, Json] = Map([("sum", Json::string("1.0"))])
  let reference : Map[String, Json] = Map([("sum", Json::number(1.0))])
  inspect(
    @verify.compare_values(
      subject,
      reference,
      ["sum"],
      "tolerance",
      1.0e-6,
      0.0,
    ).length(),
    content="1",
  )
}

///|
test "missing fields are reported" {
  let subject : Map[String, Json] = Map([])
  let reference : Map[String, Json] = Map([("n", Json::number(16.0))])
  inspect(
    @verify.compare_values(subject, reference, ["n"], "exact", 0.0, 0.0).length(),
    content="1",
  )
}
