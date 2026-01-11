// 3: implement the Clustered Deferred fullscreen vertex shader

// This shader should be very simple as it does not need all of the information passed by the the naive vertex shader.
@vertex
fn main(@builtin(vertex_index) vIdx: u32) -> @builtin(position) vec4f {
    // vtx positions on triangulated quad
    const quadPos = array(
        vec2f(-1.0, -1.0),
        vec2f(1.0, -1.0),
        vec2f(-1.0, 1.0),
        vec2f(-1.0, 1.0),
        vec2f(1.0, -1.0),
        vec2f(1.0, 1.0)
    );
    return vec4f(quadPos[vIdx], 0.0, 1.0);
}