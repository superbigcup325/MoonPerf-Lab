///|
fn type_name(value : Json) -> String {
  match value {
    Json::Null => "null"
    Json::True | Json::False => "boolean"
    Json::Number(_, ..) => "number"
    Json::String(_) => "string"
    Json::Array(_) => "array"
    Json::Object(_) => "object"
  }
}

///|
fn is_scalar(value : Json) -> Bool {
  match value {
    Json::Null | Json::Array(_) | Json::Object(_) => false
    _ => true
  }
}

///|
pub async fn read_output(
  path : String,
  fields : Array[String],
) -> (Map[String, Json], Array[String]) {
  let data = @fs.read_file(path) catch {
    _ => return ({}, ["cannot read " + path])
  }
  let text = data.text() catch {
    _ => return ({}, [path + ": output is not UTF-8 text"])
  }
  let parsed = @json.parse(text) catch {
    error => return ({}, ["invalid JSON output: " + error.to_string()])
  }
  let object = match parsed {
    Json::Object(object) => object
    _ => return ({}, ["output must be a JSON object, got " + type_name(parsed)])
  }
  let values : Map[String, Json] = Map([])
  let errors : Array[String] = []
  for field in fields {
    match object.get(field) {
      None => errors.push("missing field '" + field + "'")
      Some(value) =>
        if is_scalar(value) {
          values[field] = value
        } else {
          errors.push(
            "field '" + field + "' must be a scalar, got " + type_name(value),
          )
        }
    }
  }
  (values, errors)
}

///|
fn abs(value : Double) -> Double {
  if value < 0.0 {
    -value
  } else {
    value
  }
}

///|
pub fn compare_values(
  subject : Map[String, Json],
  reference : Map[String, Json],
  fields : Array[String],
  mode : String,
  rtol : Double,
  atol : Double,
) -> Array[String] {
  let errors : Array[String] = []
  for field in fields {
    let subject_value = subject.get(field)
    let reference_value = reference.get(field)
    match (subject_value, reference_value) {
      (None, _) => errors.push(field + ": missing from the subject output")
      (_, None) => errors.push(field + ": missing from the reference output")
      (Some(subject_value), Some(reference_value)) =>
        if mode == "exact" {
          if subject_value != reference_value {
            errors.push(
              field +
              ": " +
              subject_value.stringify() +
              " != reference " +
              reference_value.stringify(),
            )
          }
        } else {
          match reference_value {
            Json::Number(reference_number, ..) =>
              match subject_value {
                Json::Number(subject_number, ..) =>
                  if abs(subject_number - reference_number) >
                    atol + rtol * abs(reference_number) {
                    errors.push(
                      field +
                      ": |" +
                      subject_number.to_string() +
                      " - " +
                      reference_number.to_string() +
                      "| = " +
                      abs(subject_number - reference_number).to_string() +
                      " exceeds tolerance " +
                      (atol + rtol * abs(reference_number)).to_string(),
                    )
                  }
                _ =>
                  errors.push(
                    field +
                    ": type mismatch (" +
                    type_name(subject_value) +
                    " vs reference number)",
                  )
              }
            _ =>
              if subject_value != reference_value {
                errors.push(
                  field +
                  ": " +
                  subject_value.stringify() +
                  " != reference " +
                  reference_value.stringify(),
                )
              }
          }
        }
    }
  }
  errors
}
