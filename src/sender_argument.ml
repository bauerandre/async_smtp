open! Core
open! Async
open Email_message.Std

type t =
  | Auth of Email_address.t option
  | Body of [`Mime_8bit | `Mime_7bit ]
[@@deriving bin_io, sexp, compare, hash]

let of_string = function
  | "AUTH=<>" -> Ok (Auth None)
  | str when String.is_prefix str ~prefix:"AUTH=" -> begin
      let email_address = (String.drop_prefix str 5 |> String.strip) in
      match Email_address.of_string email_address with
      | Ok email_address -> Ok (Auth (Some email_address))
      | Error _ ->
        Log.Global.info "Unparsable argument to AUTH: %s" email_address;
        Ok (Auth None)
    end
  | "BODY=8BITMIME" -> Ok (Body `Mime_8bit)
  | "BODY=7BIT" -> Ok (Body `Mime_7bit)
  | str -> Or_error.errorf "Unrecognized extension to mail command: %s" str
;;

let to_string = function
  | Body `Mime_8bit -> "BODY=8BITMIME"
  | Body `Mime_7bit -> "BODY=7BIT"
  | Auth email_address ->
    match email_address with
    | None -> "AUTH=<>"
    | Some email_address -> "AUTH=" ^ (Email_address.to_string email_address)

let to_smtp_extension = function
  | Auth _ -> Smtp_extension.Auth_login
  | Body _ -> Smtp_extension.Mime_8bit_transport

let list_of_string ~allowed_extensions str =
  let open Or_error.Monad_infix in
  String.split ~on:' ' str
  |> List.filter ~f:(Fn.non String.is_empty)
  |> List.map ~f:of_string
  |> Or_error.all
  >>= fun args ->
  let has_invalid_arg =
    List.exists args ~f:(fun arg ->
      not (List.mem allowed_extensions (to_smtp_extension arg) ~equal:Smtp_extension.equal))
  in
  if has_invalid_arg then
    Or_error.errorf "Unable to parse MAIL FROM arguments: %s" str
  else
    Ok args
;;

(* Test parsing of commands to server *)
let%test_module _ =
  (module struct
    let check str extn =
      let e = of_string str |> Or_error.ok_exn in
      Polymorphic_compare.equal e extn
    ;;

    let%test _ = check "AUTH=<>" (Auth None)
    let%test _ = check "AUTH=<hello@world>" (Auth (Some (Email_address.of_string_exn "<hello@world>")))
  end)

(* Test to_string and of_string functions for symmetry *)
let%test_module _ =
  (module struct
    let check extn =
      let e = of_string (to_string extn) |> Or_error.ok_exn in
      Polymorphic_compare.equal extn e
    ;;

    let%test _ = check (Auth None)
    let%test _ = check (Auth (Some (Email_address.of_string_exn "<hello@world>")))
  end)
