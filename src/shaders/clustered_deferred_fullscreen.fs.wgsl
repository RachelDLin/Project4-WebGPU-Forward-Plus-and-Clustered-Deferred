// 3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.
@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(${bindGroup_texture}) @binding(0) var normalBuffer: texture_2d<f32>;
@group(${bindGroup_texture}) @binding(1) var albedoBuffer: texture_2d<f32>;
@group(${bindGroup_texture}) @binding(2) var worldposBuffer: texture_2d<f32>;

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1)

@fragment
fn main(@builtin(position) fragPos: vec4f) -> @location(0) vec4f
{
    // Retrieve clip space UV
    let uv = vec2i(floor(fragPos.xy));

    // sample GBuffer textures
    let normal = textureLoad(normalBuffer, uv, 0);
    let albedo = textureLoad(albedoBuffer, uv, 0);
    let worldpos = textureLoad(worldposBuffer, uv, 0);

    let clusterDims: vec3u = vec3u(${clusterDims[0]}, ${clusterDims[1]}, ${clusterDims[2]});

    // clip space
    let clipPos = camera.viewProjMat * vec4(worldpos.xyz, 1.0); 

    // perspective divide
    let ndc = clipPos.xy / clipPos.w; 

    // [-1, 1] -> [0, 1]
    let screenUV = ndc * 0.5 + 0.5;

    // Determine which cluster contains the current fragment.
    let clusterCoordX: u32 = u32(clamp(floor(screenUV.x * f32(clusterDims.x)), 0f, f32(clusterDims.x - 1u)));
    let clusterCoordY: u32 = u32(clamp(floor(screenUV.y * f32(clusterDims.y)), 0f, f32(clusterDims.y - 1u)));

    // view space (camera perspective)
    let viewPos = camera.viewMat * vec4f(worldpos.xyz, 1.0);

    // logarithmic slices in z direction
    let numSlices = f32(clusterDims.z);
    let depth = max(-viewPos.z, camera.nearClip);
    let slice = floor(
                    numSlices * 
                    log(depth / camera.nearClip) /
                    log(camera.farClip / camera.nearClip)
                );
    let clusterCoordZ: u32 = u32(clamp(slice, 0f, f32(clusterDims.z - 1u)));

    let clusterIdx: u32 = clusterCoordX + clusterCoordY * clusterDims.x + clusterCoordZ * clusterDims.x * clusterDims.y;
    let fragCluster = clusterSet.clusters[clusterIdx];

    // Retrieve the number of lights that affect the current fragment from the cluster’s data.
    let numClusterLights = fragCluster.numLights;

    // Initialize a variable to accumulate the total light contribution for the fragment.
    var totalLightContrib = vec3f(0.0, 0.0, 0.0);

    // For each light in the cluster:
    for (var clusterLightIdx = 0u; clusterLightIdx < numClusterLights; clusterLightIdx++) {

        // Access the light's properties using its index.
        let lightIdx = fragCluster.lights[clusterLightIdx];
        if (lightIdx >= lightSet.numLights) {
            continue;
        }
        let light = lightSet.lights[lightIdx];

        // Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
        // Add the calculated contribution to the total light accumulation.
        totalLightContrib += calculateLightContrib(light, worldpos.xyz, normalize(normal.xyz));
    }

    // Multiply the fragment’s diffuse color by the accumulated light contribution.
    var finalColor = albedo.rgb * totalLightContrib;

    // Return the final color, ensuring that the alpha component is set appropriately (typically to 1)
    return vec4(finalColor, 1);
}