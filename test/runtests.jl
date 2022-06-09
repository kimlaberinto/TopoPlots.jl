using Test
using LinearAlgebra, Statistics, TopoPlots, GLMakie, JLD2

example_data = JLD2.load(joinpath(@__DIR__, "example.jld2"))
pos = example_data["pos2"]
data = example_data["data"]
positions = Point2f.(pos[:,1], pos[:,2])

function test()
    f = Figure(resolution=(1000, 1000))
    interpolators = [TopoPlots.delaunay_mesh TopoPlots.claugh_tochter; TopoPlots.spline2d TopoPlots.spline2d_mne]

    s = Slider(f[:, 1], range=1:size(data, 2), startvalue=351)
    data_obs = map(s.value) do idx
        data[:, idx, 1]
    end
    for i in CartesianIndices(interpolators)
        interpolation = interpolators[i]
        TopoPlots.topoplot(f[2, 1][Tuple(i)...], positions, data_obs, interpolation=interpolation, axis=(title="$interpolation",aspect=DataAspect(),), labels = string.(1:length(positions)), colorrange=(-1, 1))
    end
    f
end

function test2()
    f = Figure(resolution=(1000, 1000))
    s = Slider(f[:, 1], range=1:size(data, 2), startvalue=351)
    data_obs = map(s.value) do idx
        data[:, idx, 1]
    end
    TopoPlots.topoplot(f[2, 1], positions, data_obs, interpolation=TopoPlots.delaunay_mesh, axis=(title="delaunay mesh",aspect=DataAspect(),), labels = string.(1:length(positions)), colorrange=(-1, 1))
    f
end