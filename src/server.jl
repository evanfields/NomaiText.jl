using HTTP, URIs

function build_response(req::HTTP.Request)
    query = queryparams(URI(req.target)) # not sure why we can't use .url, it's empty
    msg = URIs.unescapeuri(query["message"])
    str = draw_spiral(msg; base = get(query, "base", 200_003), as_string = true)
    return HTTP.Response(
        200,
        ["Content-Type" => "image/svg+xml"],
        str
    )
end

function setup_server!()
    server = HTTP.serve!() do request::HTTP.Request
        @show request
        try
            return build_response(request)
        catch e
            return HTTP.Response(400, "Error: $e")
        end
    end
    return server
end
