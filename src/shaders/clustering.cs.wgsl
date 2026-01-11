// 2: light clustering compute shader

@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;

// helper fns

// convert from screen space to view space
fn screenToView(screenPos: vec2f, ndcZ: f32) -> vec3f {
    // normalized device coordinates
    let ndc = vec4f(screenPos.x / camera.screenRes.x * 2f - 1.0,
                    screenPos.y / camera.screenRes.y * 2f - 1.0,
                    ndcZ,
                    1.0);
    // transform to screen space
    let viewPos = camera.inverseProjMat * ndc;
    return viewPos.xyz / viewPos.w;
}

// test intersection w/ cluster
fn lightClusterIntersectionTest(lightPos: vec3f, lightRadius: f32, minPos: vec3f, maxPos: vec3f) -> bool {
    // find closest pos in cluster to lightPos
    let nearestPos = clamp(lightPos, minPos, maxPos);
    let delta = nearestPos - lightPos;
    return dot(delta, delta) <= lightRadius * lightRadius;
}

// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.

// ------------------------------------
// Assigning lights to clusters:
// ------------------------------------
// For each cluster:
//     - Initialize a counter for the number of lights in this cluster.

//     For each light:
//         - Check if the light intersects with the cluster’s bounding box (AABB).
//         - If it does, add the light to the cluster's light list.
//         - Stop adding lights if the maximum number of lights is reached.

//     - Store the number of lights assigned to this cluster.

@compute
@workgroup_size(${clusterLightsWorkgroupSize[0]}, ${clusterLightsWorkgroupSize[1]}, ${clusterLightsWorkgroupSize[2]})
fn main(@builtin(global_invocation_id) globalIdx: vec3u) {

    // get cluster dims
    let clusterDims = vec3u(${clusterDims[0]}, ${clusterDims[1]}, ${clusterDims[2]});
    
    // check that there's an actual cluster at globalIdx
    if (globalIdx.x >= clusterDims.x || 
        globalIdx.y >= clusterDims.y ||
        globalIdx.z >= clusterDims.z) {
        return;
    }

    let clusterIdx: u32 = globalIdx.x + globalIdx.y * clusterDims.x + globalIdx.z * clusterDims.x * clusterDims.y;

    // Calculate the screen-space bounds for this cluster in 2D (XY).
    let screenMin = vec2f(globalIdx.xy) / vec2f(clusterDims.xy) * vec2f(camera.screenRes.xy);
    let screenMax = vec2f(globalIdx.xy + vec2u(1u, 1u)) / vec2f(clusterDims.xy) * vec2f(camera.screenRes.xy);
    
    // Calculate the depth bounds for this cluster in Z (near and far planes). Use logarithmic slices.
    let nearClip = camera.nearClip;
    let farClip = camera.farClip;
    let nearZ = -nearClip * pow(farClip / nearClip, f32(globalIdx.z) / f32(clusterDims.z));
    let farZ = -nearClip * pow(farClip / nearClip, f32(globalIdx.z + 1u) / f32(clusterDims.z));

    // Convert these screen and depth bounds into view-space coordinates.
    let viewMin = screenToView(screenMin, -1.0);
    let viewMax = screenToView(screenMax, 1.0);

    // Store the computed bounding box (AABB) for the cluster.
    let clusterMin = vec3f(min(viewMin.x, viewMax.x),
                            min(viewMin.y, viewMax.y),
                            min(nearZ, farZ));
    let clusterMax = vec3f(max(viewMin.x, viewMax.x),
                            max(viewMin.y, viewMax.y),
                            max(nearZ, farZ));

    // Initialize a counter for the number of lights in this cluster.
    var numClusterLights: u32 = 0u;

    // For each light:
    for (var lightIdx: u32 = 0u; lightIdx < lightSet.numLights; lightIdx++) {
        
        // get curr light position
        let light = lightSet.lights[lightIdx];
        let lightPos = light.pos;

        // convert from world to view space
        let lightPosView = camera.viewMat * vec4f(lightPos, 1.0);

        // Check if the light intersects with the cluster’s bounding box (AABB).
        if (lightClusterIntersectionTest(lightPosView.xyz, ${lightRadius}, clusterMin, clusterMax)) {
            // If it does, add the light to the cluster's light list.
            clusterSet.clusters[clusterIdx].lights[numClusterLights] = lightIdx;
            numClusterLights++;
        }

        // Stop adding lights if the maximum number of lights is reached.
        if (numClusterLights >= ${maxLightsPerCluster}) {
            break;
        }
    }

    // Store the number of lights assigned to this cluster.
    clusterSet.clusters[clusterIdx].numLights = numClusterLights;
}