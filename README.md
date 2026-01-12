WebGL Forward+ and Clustered Deferred Shading
======================

**University of Pennsylvania, CIS 565: GPU Programming and Architecture, Project 4**

Rachel Lin

* [LinkedIn](https://www.linkedin.com/in/rachel-lin-452834213/)
* [personal website](https://www.artstation.com/rachellin4)
* [Instagram](https://www.instagram.com/lotus_crescent/)


Tested on: Windows 11, 12th Gen Intel(R) Core(TM) i7-12700H @ 2.30GHz, NVIDIA GeForce RTX 3080 Laptop GPU (16 GB)

### Live Demo
https://racheldlin.github.io/Project4-WebGPU-Forward-Plus-and-Clustered-Deferred/


### Demo Video/GIF

<img src="img/clustered_deferred.gif" width="50%">

### Credits

- [Vite](https://vitejs.dev/)
- [loaders.gl](https://loaders.gl/)
- [dat.GUI](https://github.com/dataarts/dat.gui)
- [stats.js](https://github.com/mrdoob/stats.js)
- [wgpu-matrix](https://github.com/greggman/wgpu-matrix)


# Overview

This web app offers three different rendering pipelines: naive forward, forward+, and clustered deferred. The forward plus and clustered deferred techniques offer additional optimizations that help improve performance beyond naive forward rendering.

## Naive Forward

Naive forward rendering works by looping through each light in the scene for each pixel and summing the light contributions. The program first writes the view projection matrix to a buffer and sends it to the GPU. In the vertex shader, the view projection matrix is used to transform the position from world to screen space. The fragment shader then takes the screen space position and computes the light contribution based on the normal, position, and albedo. Since this method involves iterating through every light for every pixel, using this implementation can get expensive quickly.

## Forward+

Forward+ builds off of naive forward by breaking the screen up into tiles called clusters. Before performing lighting calculations, a compute pass finds and stores the lights that are close enough in distance to the cluster to actually have meaningful lighting contribution. In the lighting pass, the fragment shader then loops through the clusters and only computes contribution from lights within each cluster when calculating the pixel's color. This technique helps avoid expensive lighting calculations for lights that are unnecessary and don't actually contribute to the final render. 

Something to keep in mind with this implementation is that the clusters have a set array size for storing lights. When there are more lights contributing to a cluster than the maximum allowance, these lights are dropped. This can result in artifacting similar to what is shown below when the total number of lights exceeds the maximum number of lights per cluster by too much. To render more lights in the scene, the cap for the maximum number of lights per cluster needs to be raised. However, this will also come with some performance costs.

<img src="img/clustering_artifact.gif" width="50%">

## Clustered Deferred

Clustered deferred rendering takes the concept of clustering and combines it with deferred rendering. In deferred rendering, scene information like normals, albedo, and position is stored in textures called GBuffers. By only writing information for visible geometry, we avoid having overdraw for opaque geometry. However, without a hybrid deferred/forward approach, it is difficult to accurately capture properties like translucency and bounce lighting that require information on geometry that may be hidden or physically behind another object.

| Normal Buffer | Albedo Buffer	| Position Buffer	| Depth Buffer |
| --------- | --------- | --------- | --------- |
| <img src="img/normalBuffer.png" width="100%"> | <img src="img/albedoBuffer.png" width="100%"> | <img src="img/worldposBuffer.png" width="100%"> | <img src="img/depthBuffer.png" width="100%"> |

# Performance

## Number of Lights

As the total number of lights in the scene increases, the performance benefits of clustering and deferred rendering becomes apparent. With the clustering, we already see a large improvement with forward+ because for each pixel we avoid some unnecessary calculations for lights that are too far away or have too low of a light attenuation radius to contribute to the lighting for that pixel. However, combined with the use of a GBuffer and deferred lighting pass, we see some mild improvements as well because we only consider the frontmost geometry in the scene (from the camera's perspective) and do not render geometry that is not visible to the camera.

In contrast, the framerate for naive forward rendering drops quickly as the number of lights is increased. The combination of unnecessary overdraw for opaque materials, combined with unnecessary lighting calculations for irrelevant lights results in significant performance drawbacks.

<img src="img/Frame Duration vs. Number of Lights.png" width="50%">

## Max Number of Lights in a Cluster

Increasing the number of lights in a cluster results in a significant performance drop for forward+ rendering because each cluster has the same light array length and now stores more lights, causing each fragment to iterate over more lights as well (even if there aren't that many lights that are actively affecting it). This also impacts clustered deferred rendering, but the cost is not as dramatic. This is because deferred rendering only performs one lighting pass per pixel, whereas forward rendering performs one lighting pass per material fragment. Since the scene contains a lot of overlapping geometry, there are many more material fragments than pixels.

<img src="img/Frame Duration vs. Max Number of Lights Per Cluster.png" width="50%">

Since the naive forward implementation doesn't use clustering, it's performance is not impacted by this change at all. This is something that should be considered for scenes that require many lights.

## Number of Clusters

Increasing the number of clusters results in some performance costs because more intersection tests need to be made to check which lights affect each cluster. 

<img src="img/Frame Duration vs. Number of Clusters.png" width="50%">

## Clustering Workgroup Size

The clustering workgroup size defines how many threads are executed together in each workgroup during the clustering compute pass. In theory, we want to find a sweet spot for this value. Too large of a workgroup would exceed resource/register limits, resulting in fewer active workgroups and lower occupancy at any given time. Too small of a workgroup under-utilizes GPU parallelization and results in idle threads. 

<img src="img/Frame Duration vs. Workgroup Size.png" width="50%">

## Light Radius

Increasing the light attenuation radius doesn't see any significant performance costs because it doesn't impact the number of lights that we perform lighting calculations for (naive forward always looks at every light in the scene no matter its influence or distance, and the cluster light array sizes are fixed at the maximum number of lights per cluster). 

<img src="img/Frame Duration vs. Light Radius.png" width="50%">

However, increasing the light radius will increase the number of lights that _should_ influence each cluster. If this exceeds the cap for each cluster, artifacting could occur where some clusters are not as bright as they should be. The values for the light radius, maximum number of lights per cluster, and number of lights needs to be chosen carefully to optimize performance while also meeting the visual requirements for the scene.
