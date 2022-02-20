# timeseries

{{doc timeseries}}



## Attributes

### Generic

- `history = 100` sets number of samples to buffer.


## Examples

\begin{examplefigure}{}
```julia
using GLMakie
signal = Observable(1.0)

# History sets the length of the signal buffer
scene = timeseries(signal, history=25)
screen = display(scene)

record(scene, "timeseries.mp4", 1:125, framerate=30) do _
    # aquire data from e.g. a sensor:
    data = rand() * 5.0 + 2.5

    # update the signal
    signal[] = data

    # It's important to yield here though, otherwise nothing will be rendered
    sleep(1/10)
end
```
\end{examplefigure}
