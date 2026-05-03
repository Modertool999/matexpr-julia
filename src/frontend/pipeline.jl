process_matexpr(ex) = process_matexpr(CompileContext(), ex)

function process_matexpr(ctx::CompileContext, ex)
    ex = filter_line_numbers(ex)
    ex = expand_deriv(ctx, ex)
    normalize_matexpr_basic(ex)
end

function process_matexpr_structured(ctx::CompileContext, ex)
    ex = process_matexpr(ctx, ex)
    normalize_matexpr_structured(ctx, ex)
end
