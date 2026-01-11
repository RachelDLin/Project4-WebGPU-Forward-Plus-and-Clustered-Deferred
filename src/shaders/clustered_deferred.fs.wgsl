// 3: implement the Clustered Deferred G-buffer fragment shader
@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

// This shader should only store G-buffer information and should not do any shading.

struct FragmentInput
{
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
};

struct FragmentOutput
{
    @location(0) normal: vec4f,
    @location(1) albedo: vec4f,
    @location(2) worldPos: vec4f
};

@fragment
fn main(in: FragmentInput) -> FragmentOutput {
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }

    return FragmentOutput(vec4(normalize(in.nor), 0.0), diffuseColor, vec4(in.pos, 1));
}