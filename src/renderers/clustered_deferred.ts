import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';
import { Stage } from '../stage/stage';

export class ClusteredDeferredRenderer extends renderer.Renderer {
    // 3: add layouts, pipelines, textures, etc. needed for Clustered Deferred here
    sceneUniformsBindGroupLayout: GPUBindGroupLayout;
    sceneUniformsBindGroup: GPUBindGroup;
    GBufferPipeline: GPURenderPipeline;

    deferredPassBindGroupLayout: GPUBindGroupLayout;
    deferredPassBindGroup: GPUBindGroup;
    deferredPassPipeline: GPURenderPipeline;

    normalTexture: GPUTexture;
    normalTextureView: GPUTextureView;

    albedoTexture: GPUTexture;
    albedoTextureView: GPUTextureView;

    worldposTexture: GPUTexture;
    worldposTextureView: GPUTextureView;

    depthTexture: GPUTexture;
    depthTextureView: GPUTextureView;

    constructor(stage: Stage) {
        super(stage);

        // 3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
        // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass
        
        this.normalTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.normalTextureView = this.normalTexture.createView();

        this.albedoTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.albedoTextureView = this.albedoTexture.createView();

        this.worldposTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.worldposTextureView = this.worldposTexture.createView();

        this.depthTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "depth24plus",
            usage: GPUTextureUsage.RENDER_ATTACHMENT
        });
        this.depthTextureView = this.depthTexture.createView();
        
        this.sceneUniformsBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "scene uniforms bind group layout",
            entries: [
                { // camera
                    binding: 0,
                    visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                    buffer: { type: "uniform"}
                },
                { // lightSet
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }
                },
                { // clusterSet
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }
                }
            ]
        });

        this.sceneUniformsBindGroup = renderer.device.createBindGroup({
            label: "scene uniforms bind group",
            layout: this.sceneUniformsBindGroupLayout,
            entries: [
                { // camera
                    binding: 0,
                    resource: { buffer: this.camera.uniformsBuffer }
                }, 
                { // lightSet
                    binding: 1,
                    resource: { buffer: this.lights.lightSetStorageBuffer }
                }, 
                { // clusterSet
                    binding: 2,
                    resource: { buffer: this.lights.clusterSetStorageBuffer }
                }
            ]
        });

        this.GBufferPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "GBuffer pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    renderer.modelBindGroupLayout,
                    renderer.materialBindGroupLayout
                ]
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "GBuffer vert shader",
                    code: shaders.naiveVertSrc
                }),
                buffers: [ renderer.vertexBufferLayout ]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "GBuffer frag shader",
                    code: shaders.clusteredDeferredFragSrc,
                }),
                targets: [
                    { // normal
                        format: "rgba16float",
                    },
                    { // albedo
                        format: "rgba16float",
                    },
                    { // worldpos
                        format: "rgba16float",
                    }
                ]
            }
        });

        this.deferredPassBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "clustered deferred pass bind group layout",
            entries: [
                { // normal
                    binding: 0,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {}
                },
                { // albedo
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {}
                },
                { // worldpos
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {}
                }
            ]
        });

        this.deferredPassBindGroup = renderer.device.createBindGroup({
            label: "clustered deferred pass bind group",
            layout: this.deferredPassBindGroupLayout,
            entries: [
                { // normal
                    binding: 0,
                    resource: this.normalTextureView
                },
                { // albedo
                    binding: 1,
                    resource: this.albedoTextureView
                },
                { // worldpos
                    binding: 2,
                    resource: this.worldposTextureView
                }
            ]
        });

        this.deferredPassPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "clustered deferred lighting pass pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    this.deferredPassBindGroupLayout
                ]
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred lighting pass vert shader",
                    code: shaders.clusteredDeferredFullscreenVertSrc
                }),
                buffers: []
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred lighting pass frag shader",
                    code: shaders.clusteredDeferredFullscreenFragSrc,
                }),
                targets: [
                    {
                        format: renderer.canvasFormat,
                    }
                ]
            }
        });
    }

    override draw() {
        // 3: run the Forward+ rendering pass:
        const encoder = renderer.device.createCommandEncoder();
        const canvasTextureView = renderer.context.getCurrentTexture().createView();

        // - run the clustering compute shader
        this.lights.doLightClustering(encoder);
        
        // - run the G-buffer pass, outputting position, albedo, and normals
        const renderPass = encoder.beginRenderPass({
            label: "GBuffer render pass",
            colorAttachments: [
                {
                    view: this.normalTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                },
                {
                    view: this.albedoTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }, 
                {
                    view: this.worldposTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
        });
        renderPass.setPipeline(this.GBufferPipeline);
        renderPass.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);

        this.scene.iterate(node => {
            renderPass.setBindGroup(shaders.constants.bindGroup_model, node.modelBindGroup);
        }, material => {
            renderPass.setBindGroup(shaders.constants.bindGroup_material, material.materialBindGroup);
        }, primitive => {
            renderPass.setVertexBuffer(0, primitive.vertexBuffer);
            renderPass.setIndexBuffer(primitive.indexBuffer, 'uint32');
            renderPass.drawIndexed(primitive.numIndices);
        });

        renderPass.end();

        // - run the fullscreen pass, which reads from the G-buffer and performs lighting calculations
        const deferredRenderPass = encoder.beginRenderPass({
            label: "deferred lighting render pass",
            colorAttachments: [
                {
                    view: canvasTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                },
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
        });
        deferredRenderPass.setPipeline(this.deferredPassPipeline);
        deferredRenderPass.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);
        deferredRenderPass.setBindGroup(shaders.constants.bindGroup_texture, this.deferredPassBindGroup);
        deferredRenderPass.draw(6); // 6 verts for a quad

        deferredRenderPass.end();

        renderer.device.queue.submit([encoder.finish()]);
    }
}
