@recipe(TopoPlot, data, positions) do scene
    return Attributes(
        colormap = Reverse(:RdBu),
        colorrange = Makie.automatic,
        sensors = true,
        interpolation = ClaughTochter(),
        bounding_geometry = Circle,
        padding = 0.1,
        pad_value = 0.0,
        resolution = (512, 512),
        labels = nothing,
        label_text = nothing,
        label_scatter = nothing,
        contours = nothing
    )
end

"""
    topoplot(data::Vector{<:Real}, positions::Vector{<: Point2})

Creates an irregular interpolation for each `data[i]` point at `positions[i]`.

# Attributes

* `colormap = Reverse(:RdBu)`
* `colorrange = automatic`
* `labels::Vector{<:String}` = nothing: names for each data point
* `interpolation::Interpolator = ClaughTochter()`: Applicable interpolators are $(join(subtypes(TopoPlots.Interpolator), ", "))
* `bounding_geometry = Circle`: the geometry added to the points, to create a smooth boundary. Can be `Rect` or `Circle`.
* `padding = 0.1`: padding applied to `bounding_geometry`
* `pad_value = 0.0`: data value filled in for each added position from `bounding_geometry`
* `resolution = (512, 512)`: resolution of the interpolation
* `label_text = nothing`:
    * true: add text plot for each position from `labels`
    * NamedTuple: Attributes get passed to the Makie.text! call.
* `label_scatter = nothing`:
    * true: add point for each position with
    * NamedTuple: Attributes get passed to the Makie.scatter! call.
* `contours = nothing`:
    * true: add point for each position
    * NamedTuple: Attributes get passed to the Makie.contour! call.

# Example

```julia
using TopoPlots, CairoMakie
topoplot(rand(10), rand(Point2f, 10); contours=(color=:red, linewidth=2))
```
"""
topoplot

function Makie.plot!(p::TopoPlot)
    npositions = Observable(0; ignore_equal_values=true)
    geometry = lift(enclosing_geometry, p.bounding_geometry, p.positions, p.padding; ignore_equal_values=true)
    p.geometry = geometry # store geometry in plot object, so others can access it
    # positions changes with with data together since it gets into convert_arguments
    positions = lift(identity, p.positions; ignore_equal_values=true)
    padded_position = lift(positions, geometry, p.resolution; ignore_equal_values=true) do positions, geometry, resolution
        points_padded = append!(copy(positions), decompose(Point2f, geometry))
        npositions[] = length(points_padded)
        return points_padded
    end

    xg = Observable(LinRange(0f0, 1f0, p.resolution[][1]); ignore_equal_values=true)
    yg = Observable(LinRange(0f0, 1f0, p.resolution[][2]); ignore_equal_values=true)

    f = onany(geometry, p.resolution) do geom, resolution
        xmin, ymin = minimum(geom)
        xmax, ymax = maximum(geom)
        xg[] = LinRange(xmin, xmax, resolution[1])
        yg[] = LinRange(ymin, ymax, resolution[2])
        return
    end
    notify(p.resolution) # trigger above (we really need `update=true` for onany)

    padded_data = lift(pad_data, p.data, npositions, p.pad_value)

    if p.interpolation[] isa DelaunayMesh
        # TODO, delaunay works very differently from the other interpolators, so we can't switch interactively between them
        m = lift(delaunay_mesh, padded_position)
        mesh!(p, m, color=padded_data, colorrange=p.colorrange, colormap=p.colormap, shading=false)
    else
        data = lift(p.interpolation, xg, yg, padded_position, padded_data) do interpolation, xg, yg, points, data
            return interpolation(xg, yg, points, data)
        end
        heatmap!(p, xg, yg, data, colormap=p.colormap, colorrange=p.colorrange, interpolate=true)
        contours = to_value(p.contours)
        if !isnothing(contours)
            defaults = Attributes(color=(:black, 0.5), linestyle=:dot, levels=6)
            attributes = contours === true ? defaults : merge(contours, defaults)
            contour!(p, xg, yg, data; attributes...)
        end
    end
    label_scatter = to_value(p.label_scatter)
    if !isnothing(label_scatter)
        defaults = Attributes(markersize=5, color=p.data, colormap=p.colormap, colorrange=p.colorrange, strokecolor=:black, strokewidth=1)
        attributes = label_scatter === true ? defaults : merge(label_scatter, defaults)
        scatter!(p, p.positions; attributes...)
    end
    if !isnothing(p.labels[])
        label_text = to_value(p.label_text)
        if !isnothing(label_text)
            defaults = Attributes(align=(:right, :top),)
            attributes = label_text === true ? defaults : merge(label_text, defaults)
            text!(p, p.positions, text=p.labels; attributes...)
        end
    end
    return
end

"""
    enclosing_geometry(G::Type{<: Geometry}, positions, enlarge=0.0)

Returns the Geometry of Type `G`, that best fits all positions.
The Geometry can be enlarged by 1.x, so e.g. `enclosing_geometry(Circle, positions, 0.1)` will return a Circle that encloses all positions with a padding of 10%.
"""
function enclosing_geometry(::Type{Circle}, positions, enlarge=0.0)
    middle = mean(positions)
    radius, idx = findmax(x-> norm(x .- middle), positions)
    return Circle(middle, radius * (1 + enlarge))
end

function enclosing_geometry(::Type{Rect}, positions, enlarge=0.0)
    rect = Rect2f(positions)
    w = widths(rect)
    padded_w = w .* (1 + 2enlarge)
    mini = minimum(rect) .- ((padded_w .- w) ./ 2)
    return Rect2f(mini, padded_w)
end

"""
    pad_boundary(::Type{Geometry}, positions, enlarge=0.2) where Geometry

Adds new points to positions, adding the boundary from enclosing all positions with `Geometry`.
See [`TopoPlots.enclosing_geometry`](@ref) for more details about the boundary.
"""
function pad_boundary!(::Type{Geometry}, positions, enlarge=0.2) where Geometry
    c = enclosing_geometry(Geometry, positions, enlarge)
    return append!(positions, decompose(Point2f, c))
end

function pad_data(data::AbstractVector, positions::AbstractVector, value::Number)
    pad_data(data, length(positions), value)
end

function pad_data(data::AbstractVector, npositions::Integer, value::Number)
    ndata = length(data)
    if npositions == ndata
        return data
    elseif npositions < ndata
        error("To pad the data for new positions, we need more positions than data points")
    else
        vcat(data, fill(value, npositions - ndata))
    end
end