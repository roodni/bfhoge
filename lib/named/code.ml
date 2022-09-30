(** 中間言語のコード
    解析のため追加情報を付与できる
*)
type 'a t = 'a annotated list
and 'a annotated = { cmd:'a cmd; annot:'a }
and 'a cmd =
  | Add of int * Sel.t
  | Put of Sel.t
  | Get of Sel.t
  | Shift of { n:int; index:(Sel.t * Id.t); followers:Id.t list }
  | Loop of Sel.t * 'a t
  | LoopIndex of (Sel.t * Id.t * 'a t)
  | If of Sel.t * 'a t * 'a t
  | Reset of Sel.t

(** アノテーション付きコマンド1つ単位で単純な書き換えを行う
    コマンドの書き換えが未定義のとき再帰的に適用する
*)
let rec map f code =
  List.map
    (fun annotated ->
      let cmd_opt, annot = f annotated in
      let cmd =  match cmd_opt with
        | None -> cmd_map f annotated.cmd
        | Some cmd -> cmd
      in
      { cmd; annot }
    )
    code
and cmd_map f = function
  | Add (n, sel) -> Add (n, sel)
  | Put sel -> Put sel
  | Get sel -> Get sel
  | Reset sel -> Reset sel
  | Shift params -> Shift params
    (* ↑コンストラクタで新しい値を構成しないと型が合わない *)
  | Loop (sel, code) ->
      Loop (sel, map f code)
  | LoopIndex (sel, id, code) ->
      LoopIndex (sel, id, map f code)
  | If (sel, thn, els) ->
      If (sel, map f thn, map f els)

(** アノテーションだけを書き換える *)
let annot_map f code =
  map (fun { annot; _ } -> (None, f annot)) code
let cmd_annot_map f cmd =
  cmd_map (fun { annot; _ } -> (None, f annot)) cmd

let delete_annot code = annot_map (Fun.const ()) code

let from_list cmd_list =
  List.map
    (fun cmd -> { cmd=cmd_annot_map (Fun.const ()) cmd; annot=() })
    cmd_list

let shift_followers n (arr_sel, idx_id) followers =
  followers
  |> List.map
    (fun follower_id ->
      let src_sel = Sel.concat_member_to_index_tail (arr_sel, idx_id) follower_id 0 in
      let dest_sel = Sel.concat_member_to_index_tail (arr_sel, idx_id) follower_id n in
      [ Loop
          ( src_sel,
            [ Add (-1, src_sel);
              Add (1, dest_sel);
            ] |> from_list
          )
      ]
    )
  |> List.flatten |> from_list

let desugar_LoopIndex (arr_sel, idx_id, loop) =
  let cond_sel = Sel.concat_member_to_index_tail (arr_sel, idx_id) idx_id (-1) in
  from_list [ Loop (cond_sel, loop) ]

(** イディオム[-]を専用コマンドに変換する *)
let convert_idioms code =
  map
    (fun { cmd; _ } -> match cmd with
      | Loop (sel1, [{ cmd=Add(-1, sel2); _ }])
        when sel1 = sel2 ->
          (Some (Reset sel1), ())
      | Add _ | Put _ | Get _ | Shift _ | Reset _
      | Loop _ | LoopIndex _ | If _ ->
          (None, ())
    )
    code