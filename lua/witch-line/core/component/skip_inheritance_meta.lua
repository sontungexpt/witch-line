return {
    -- identity / registry state
    id = true,
    _loaded = true,
    _renderable = true,

    -- runtime cache / computed state
    _hidden = true,
    _use_returned_style = true,
    _hl_name = true,
    _left_hl_name = true,
    _right_hl_name = true,

    --- Considering allow inherit this fiedl
    init = true,

    -- lifecycle hooks (IMPORTANT: should NOT be inherited blindly)
    update = true,
    pre_update = true,
    post_update = true,
    with_session = true, -- nên skip luôn

    -- framework internal flags
    _click_handler = true,
    _plug_provided = true,
}
