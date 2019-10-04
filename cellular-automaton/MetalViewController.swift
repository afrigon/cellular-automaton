//
//  MetalViewController.swift
//  cellular-automaton
//
//  Created by Alexandre Frigon on 2018-10-15.
//  Copyright © 2018 Frigstudio. All rights reserved.
//

import Metal
import Cocoa

struct Cell {
    var quad: Quad
    var color: Float
    
    init(_ quad: Quad, color: Float) {
        self.quad = quad
        self.color = color
    }
    
    public func draw(_ encoder: MTLRenderCommandEncoder?) {
        self.quad.draw(self.color, encoder)
    }
}

class Quad {
    private var vbo: MTLBuffer?
    
    init(x: Float, y: Float, width: Float, height: Float, _ device: MTLDevice) {
        var vao = [Float]()
        vao.append(x)
        vao.append(y)
        
        vao.append(x + width)
        vao.append(y)
        
        vao.append(x + width)
        vao.append(y + height)
        
        vao.append(x)
        vao.append(y)
        
        vao.append(x + width)
        vao.append(y + height)
        
        vao.append(x)
        vao.append(y + height)
        
        self.vbo = device.makeBuffer(bytes: vao, length: vao.count * MemoryLayout<Float>.size, options: [])
    }
    
    public func draw(_ color: Float, _ encoder: MTLRenderCommandEncoder?) {
        encoder?.setVertexBuffer(self.vbo, offset: 0, index: 0)
        encoder?.setFragmentBytes([color], length: 32, index: 0)
        encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
}

class MetalViewController: NSViewController {
    private var device: MTLDevice!
    private var metalLayer: CAMetalLayer!
    private var pipelineState: MTLRenderPipelineState!
    private var commandQueue: MTLCommandQueue!
    private var displayLink: DisplayLink!
    
    private var cells: [[Cell]] = [[Cell]]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.device = MTLCreateSystemDefaultDevice()
        
        self.metalLayer = CAMetalLayer()
        self.metalLayer.device = self.device
        self.metalLayer.pixelFormat = .bgra8Unorm
        self.metalLayer.framebufferOnly = true
        self.metalLayer.frame = self.view.layer!.frame
        self.view.layer?.addSublayer(self.metalLayer)
        
        self.initializeData(width: Float(self.view.layer!.frame.width), height: Float(self.view.layer!.frame.height))
        
        self.pipelineState = self.compilePipeline()
        self.commandQueue = self.device.makeCommandQueue()
        self.displayLink = DisplayLink(onQueue: DispatchQueue.main)
        self.displayLink.callback = self.gameloop
        self.displayLink.start()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        self.displayLink.suspend()
    }
    
    private func initializeData(width: Float, height: Float, cellSize: Float = 5.0) {
        for y in 0..<Int(height / cellSize) {
            var row = [Cell]()
            for x in 0..<Int(width / cellSize) {
                let originX: Float = (Float(x) * cellSize) / (width / 2) - 1
                let originY: Float = (Float(y) * cellSize) / (height / 2) - 1
                let quad = Quad(x: originX, y: -originY, width: cellSize, height: -cellSize, self.device)
                row.append(Cell(quad, color: Float(Int.random(in: 0...1))))
            }
            self.cells.append(row)
        }
    }
    
    private func compilePipeline() -> MTLRenderPipelineState {
        let defaultLibrary = self.device.makeDefaultLibrary()
        let vertexProgram = defaultLibrary?.makeFunction(name: "static_vertex")
        let fragmentProgram = defaultLibrary?.makeFunction(name: "static_fragment")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexProgram
        pipelineDescriptor.fragmentFunction = fragmentProgram
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        guard let pipelineState = try? self.device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            fatalError("Could not compile pipeline with curent configuration")
        }
        
        return pipelineState
    }
    
    private func gameloop() {
        self.update()
        autoreleasepool {
            self.render()
        }
    }
    
    private func update() {
        self.applyRules()
    }
    
    private func count(_ x: Int, _ y: Int) -> Int {
        var count: Int = 0
        for dx in -1...1 {
            for dy in -1...1 {
                let nx = x + dx
                let ny = y + dy
                
                if nx <= -1 || nx >= self.cells[y].count
                || ny <= -1 || ny >= self.cells.count
                || (dx == 0 && dy == 0) {
                    continue
                }
                
                if (self.cells[y][x].color == 1.0) {
                    count += 1
                }
            }
        }
        return count
    }
    
    private func applyRules() {
        struct Updates {
            var x: Int
            var y: Int
            var state: Int
            init(_ x: Int, _ y: Int, _ state: Int) {
                self.x = x
                self.y = y
                self.state = state
            }
        }
        var nextGeneration = [Updates]()
        
        for y in 0..<self.cells.count {
            for x in 0..<self.cells[y].count {
                let living: Int = self.count(x, y)
                
                if self.cells[y][x].color == 1.0 {
                    if living < 2 || living > 3 {
                        nextGeneration.append(Updates(x, y, 0))
                    }
                } else {
                    if living == 3 {
                        nextGeneration.append(Updates(x, y, 1))
                    }
                }
            }
        }
        
        for update in nextGeneration {
            self.cells[update.y][update.x].color = Float(update.state)
        }
    }
    
    private func render() {
        let commandBuffer = self.commandQueue.makeCommandBuffer()
        
        guard let drawable = self.metalLayer.nextDrawable() else { return }
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 100.0, blue: 100.0, alpha: 1.0)
        
        let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        encoder?.setRenderPipelineState(pipelineState)
        
        for row in self.cells {
            for cell in row {
                cell.draw(encoder)
            }
        }
        
        encoder?.endEncoding()
        
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
