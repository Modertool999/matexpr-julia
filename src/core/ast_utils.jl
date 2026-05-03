filter_line_numbers(e::Expr) =
    let args = filter(a -> !(a isa LineNumberNode), e.args)
        Expr(e.head, filter_line_numbers.(args)...)
    end

filter_line_numbers(e) = e