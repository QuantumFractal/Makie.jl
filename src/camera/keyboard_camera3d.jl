struct KeyCamera3D <: AbstractCamera
    eyeposition::Node{Vec3f0}
    lookat::Node{Vec3f0}
    upvector::Node{Vec3f0}

    fov::Node{Float32}
    near::Node{Float32}
    far::Node{Float32}

    pulser::Node{Float64}

    #key_attr::Dict{Symbol, Keyboard.Button}
    attributes::Attributes
end

to_node(x) = Node(x)
to_node(n::Node) = n

"""

keyboard keys can be sets too
"""
function keyboard_cam!(scene; kwargs...)
    kwdict = Dict(kwargs)
    attributes = merged_get!(:cam3d, scene, Attributes(kwargs)) do 
        Attributes(
            # Keyboard
            # Translations
            up_key        = Keyboard.left_shift,
            down_key      = Keyboard.left_control,
            left_key      = Keyboard.j,
            right_key     = Keyboard.l,
            forward_key   = Keyboard.w,
            backward_key  = Keyboard.s,
            # Zooms
            zoom_in_key   = Keyboard.i,
            zoom_out_key  = Keyboard.k,
            # Rotations
            pan_left_key  = Keyboard.a,
            pan_right_key = Keyboard.d,
            tilt_up_key   = Keyboard.r,
            tilt_down_key = Keyboard.f,
            roll_clockwise_key        = Keyboard.e,
            roll_counterclockwise_key = Keyboard.q,
            # Mouse
            translation_button = Mouse.right,
            rotation_button    = Mouse.left,
            # Settings
            # TODO differentiate mouse and keyboard speeds
            rotationspeed = 1f0,
            translationspeed = 1f0,
            zoomspeed = 1f0,
            fov = 45f0, # base fov
            rotation_center = :lookat,
            enable_crosshair = true,
            update_rate = 1/30,
            projectiontype = Perspective
        )
    end

    cam = KeyCamera3D(
        to_node(pop!(attributes, :eyeposition, Vec3f0(3))),
        to_node(pop!(attributes, :lookat,      Vec3f0(0))),
        to_node(pop!(attributes, :upvector,    Vec3f0(0, 0, 1))),

        to_node(get(kwdict, :fov, 45f0)),
        to_node(pop!(kwdict, :near, 0.01f0)),
        to_node(pop!(kwdict, :far, 100f0)),

        Node(-1.0),

        attributes
    )

    disconnect!(camera(scene))

    # ticks every so often to get consistent position updates.
    on(cam.pulser) do prev_time
        current_time = time()
        active = on_pulse(scene, cam, Float32(current_time - prev_time))
        @async if active
            sleep(cam.attributes.update_rate[])
            cam.pulser[] = current_time
        else
            cam.pulser.val = -1.0
        end
    end

    keynames = (
        :up_key, :down_key, :left_key, :right_key, :forward_key, :backward_key, 
        :zoom_in_key, :zoom_out_key, :pan_left_key, :pan_right_key, :tilt_up_key, 
        :tilt_down_key, :roll_clockwise_key, :roll_counterclockwise_key
    )
    # This stops working with camera(scene)?
    # camera(scene),
    on(events(scene).keyboardbutton) do event
        if event.action == Keyboard.press && cam.pulser[] == -1.0 &&
            any(key -> ispressed(scene, cam.attributes[key][]), keynames)
              
            cam.pulser[] = time()
            return true
        end
        return false
    end
   
    add_translation!(scene, cam, attributes[:translation_button])
    add_rotation!(scene, cam, attributes[:rotation_button])
    
    cameracontrols!(scene, cam)
    on(camera(scene), scene.px_area) do area
        # update cam when screen ratio changes
        update_cam!(scene, cam)
    end
    center!(scene)
    
    # TODO how do you clean this up?
    scatter!(scene, 
        map(p -> [p], cam.lookat), 
        marker = '+', 
        # TODO this needs explicit cleanup
        markersize = lift(rect -> 0.01f0 * sum(widths(rect)), scene.data_limits), 
        markerspace = SceneSpace, color = :red, visible = cam.attributes[:enable_crosshair]
    )

    cam
end


# TODO switch button and key because this is the wrong order
function add_translation!(scene, cam::KeyCamera3D, button = Node(Mouse.right))
    translationspeed = cam.attributes[:translationspeed]
    zoomspeed = cam.attributes[:zoomspeed]
    last_mousepos = RefValue(Vec2f0(0, 0))
    dragging = RefValue(false)

    # drag start/stop
    on(camera(scene), scene.events.mousebutton) do event
        if event.button == button[]
            if event.action == Mouse.press && is_mouseinside(scene)
                last_mousepos[] = mouseposition_px(scene)
                dragging[] = true
                return true
            elseif event.action == Mouse.release && dragging[]
                mousepos = mouseposition_px(scene)
                dragging[] = false
                diff = (last_mousepos[] - mousepos) * 0.01f0 * translationspeed[]
                last_mousepos[] = mousepos
                translate_cam!(scene, cam, Vec3f0(diff[1], diff[2], 0f0))
                update_cam!(scene, cam)
                return true
            end
        end
        return false
    end

    # in drag
    on(camera(scene), scene.events.mouseposition) do mp
        if dragging[] && ispressed(scene, button[])
            mousepos = screen_relative(scene, mp)
            diff = (last_mousepos[] .- mousepos) * 0.01f0 * translationspeed[]
            last_mousepos[] = mousepos
            translate_cam!(scene, cam, Vec3f0(diff[1], diff[2], 0f0))
            update_cam!(scene, cam)
            return true
        end
        return false
    end

    on(camera(scene), scene.events.scroll) do scroll
        if is_mouseinside(scene)
            cam_res = Vec2f0(widths(scene.px_area[]))
            mouse_pos_normalized = mouseposition_px(scene) ./ cam_res
            mouse_pos_normalized = 2*mouse_pos_normalized .- 1f0
            zoom = (1f0 + 0.1f0 * zoomspeed[]) ^ -scroll[2]
            _zoom!(scene, cam, mouse_pos_normalized, zoom)
            update_cam!(scene, cam)
            return true
        end
        return false
    end
end

function add_rotation!(scene, cam::KeyCamera3D, button = Node(Mouse.left))
    rotationspeed = cam.attributes[:rotationspeed]
    last_mousepos = RefValue(Vec2f0(0, 0))
    dragging = RefValue(false)
    e = events(scene)

    on(camera(scene), e.mousebutton) do event
        if event.button == button[]
            if event.action == Mouse.press && is_mouseinside(scene)
                last_mousepos[] = mouseposition_px(scene)
                dragging[] = true
                return true
            elseif event.action == Mouse.release && dragging[]
                mousepos = mouseposition_px(scene)
                dragging[] = false
                rot_scaling = rotationspeed[] * (e.window_dpi[] * 0.005)
                mp = (last_mousepos[] - mousepos) * 0.01f0 * rot_scaling
                last_mousepos[] = mousepos
                rotate_cam!(scene, cam, Vec3f0(-mp[2], mp[1], 0f0))
                update_cam!(scene, cam)
                return true
            end
        end
        return false
    end

    on(camera(scene), e.mouseposition) do mp
        if dragging[]
            mousepos = screen_relative(scene, mp)
            rot_scaling = rotationspeed[] * (e.window_dpi[] * 0.005)
            mp = (last_mousepos[] .- mousepos) * 0.01f0 * rot_scaling
            last_mousepos[] = mousepos
            rotate_cam!(scene, cam, Vec3f0(-mp[2], mp[1], 0f0))
            update_cam!(scene, cam)
            return true
        end
        return false
    end
end


function on_pulse(scene, cc, timestep)
    attr = cc.attributes

    right = ispressed(scene, attr[:right_key][])
    left = ispressed(scene, attr[:left_key][])
    up = ispressed(scene, attr[:up_key][])
    down = ispressed(scene, attr[:down_key][])
    backward = ispressed(scene, attr[:backward_key][])
    forward = ispressed(scene, attr[:forward_key][])
    translating = right || left || up || down || backward || forward

    if translating
        lookat = cc.lookat[]
        eyepos = cc.eyeposition[]
        viewdir = lookat - eyepos
        translation = attr[:translationspeed][] * norm(viewdir) * timestep * 
            Vec3f0(right - left, up - down, backward - forward)

        translate_cam!(scene, cc, translation)
    end

    up = ispressed(scene, attr[:tilt_up_key][])
    down = ispressed(scene, attr[:tilt_down_key][])
    left = ispressed(scene, attr[:pan_left_key][])
    right = ispressed(scene, attr[:pan_right_key][])
    counterclockwise = ispressed(scene, attr[:roll_counterclockwise_key][])
    clockwise = ispressed(scene, attr[:roll_clockwise_key][])
    rotating = up || down || left || right || counterclockwise || clockwise

    if rotating
        # rotations around x/y/z axes
        angles = attr[:rotationspeed][] * timestep * 
            Vec3f0(up - down, left - right, counterclockwise - clockwise)

        rotate_cam!(scene, cc, angles)
    end

    zoom_out = ispressed(scene, attr[:zoom_out_key][])
    zoom_in = ispressed(scene, attr[:zoom_in_key][])
    zooming = zoom_out || zoom_in

    if zooming
        zoom = (1f0 + attr[:zoomspeed][] * timestep) ^ (zoom_out - zoom_in)
        _zoom!(scene, cc, Vec3f0(0), zoom)
    end

    if translating || rotating || zooming
        update_cam!(scene, cc)
        return true
    else 
        return false 
    end
end


function translate_cam!(scene, cc, translation)
    # This uses a camera based coordinate system where
    # x expands right, y expands up and z expands towards the screen
    lookat = cc.lookat[]
    eyepos = cc.eyeposition[]
    up = cc.upvector[]          # +y
    viewdir = lookat - eyepos   # -z
    right = cross(viewdir, up)  # +x

    trans = normalize(right) * translation[1] + 
        normalize(up) * translation[2] - normalize(viewdir) * translation[3]

    cc.eyeposition[] = eyepos + trans
    cc.lookat[] = lookat + trans
    nothing
end

function rotate_cam!(scene, cc::KeyCamera3D, angles)
    # This applies rotations around the x/y/z axis of the camera coordinate system
    # x expands right, y expands up and z expands towards the screen
    lookat = cc.lookat[]
    eyepos = cc.eyeposition[]
    up = cc.upvector[]          # +y
    viewdir = lookat - eyepos   # -z
    right = cross(viewdir, up)  # +x

    rotation = qrotation(right, angles[1]) * qrotation(up, angles[2]) * 
                qrotation(-viewdir, angles[3])
    
    cc.upvector[] = rotation * up
    viewdir = rotation * viewdir
    if cc.attributes[:rotation_center] == :lookat
        cc.eyeposition[] = lookat - viewdir    
    else
        cc.lookat[] = eyepos + viewdir
    end
    nothing
end

function _zoom!(scene::Scene, cc::KeyCamera3D, mouse_pos_normalized, zoom::AbstractFloat)
    # lookat = cc.lookat[]
    eyepos = cc.eyeposition[]
    # viewdir = lookat - eyepos
    # cc.eyeposition[] = lookat - zoom * viewdir
    cc.fov[] = clamp(zoom * cc.fov[], 0.01f0, 175f0)
    nothing
end


function update_cam!(scene::Scene, cam::KeyCamera3D)
    @extractvalue cam (fov, near, lookat, eyeposition, upvector)

    zoom = norm(lookat - eyeposition)
    # TODO this means you can't set FarClip... SAD!
    # TODO use boundingbox(scene) for optimal far/near
    far = max(zoom * 5f0, 30f0)
    aspect = Float32((/)(widths(scene.px_area[])...))
    proj = perspectiveprojection(fov, aspect, near, far)
    view = Makie.lookat(eyeposition, lookat, upvector)

    scene.camera.projection[] = proj
    scene.camera.view[] = view
    scene.camera.projectionview[] = proj * view
    scene.camera.eyeposition[] = cam.eyeposition[]
end

# TODO
function update_cam!(scene::Scene, camera::KeyCamera3D, area3d::Rect)
    @extractvalue camera (fov, near, lookat, eyeposition, upvector)
    bb = FRect3D(area3d)
    width = widths(bb)
    half_width = width/2f0
    lower_corner = minimum(bb)
    middle = maximum(bb) - half_width
    old_dir = normalize(eyeposition .- lookat)
    camera.lookat[] = middle
    neweyepos = middle .+ (1.2*norm(width) .* old_dir)
    camera.eyeposition[] = neweyepos
    camera.upvector[] = Vec3f0(0,0,1)
    camera.near[] = 0.1f0 * norm(widths(bb))
    camera.far[] = 3f0 * norm(widths(bb))
    update_cam!(scene, camera)
    return
end

# used in general and by on_pulse
function update_cam!(scene::Scene, camera::KeyCamera3D, eyeposition, lookat, up = Vec3f0(0, 0, 1))
    camera.lookat[] = Vec3f0(lookat)
    camera.eyeposition[] = Vec3f0(eyeposition)
    camera.upvector[] = Vec3f0(up)
    update_cam!(scene, camera)
    return
end