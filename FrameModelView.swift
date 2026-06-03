import SwiftUI
import SceneKit

struct FrameModelView: UIViewRepresentable {

    @Binding var isInteracting: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SCNView {

        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        view.scene = scene

        // Camera
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.1
        camera.zFar = 1000
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(4,5,500)

        scene.rootNode.addChildNode(cameraNode)

        context.coordinator.cameraNode = cameraNode
        context.coordinator.originalCameraPosition = cameraNode.position

        // Lights

        let keyLightNode = SCNNode()
        let keyLight = SCNLight()
        keyLight.type = .omni
        keyLight.intensity = 850
        keyLightNode.light = keyLight
        keyLightNode.position = SCNVector3(6,8,12)
        scene.rootNode.addChildNode(keyLightNode)

        let fillLightNode = SCNNode()
        let fillLight = SCNLight()
        fillLight.type = .omni
        fillLight.intensity = 300
        fillLightNode.light = fillLight
        fillLightNode.position = SCNVector3(-6,3,10)
        scene.rootNode.addChildNode(fillLightNode)

        let rimLightNode = SCNNode()
        let rimLight = SCNLight()
        rimLight.type = .omni
        rimLight.intensity = 220
        rimLightNode.light = rimLight
        rimLightNode.position = SCNVector3(0,4,-10)
        scene.rootNode.addChildNode(rimLightNode)

        let ambientNode = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 180
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        // Spin node

        let spinNode = SCNNode()
        scene.rootNode.addChildNode(spinNode)
        context.coordinator.spinNode = spinNode

        // Load model

        guard let url = Bundle.main.url(forResource: "FullBody_v3", withExtension: "usdz") else {
            print("Model not found")
            return view
        }

        do {

            let modelScene = try SCNScene(url: url)
            let root = SCNNode()

            for child in modelScene.rootNode.childNodes {
                root.addChildNode(child.clone())
            }

            let modelNode = root.flattenedClone()

            let (min,max) = modelNode.boundingBox

            let center = SCNVector3(
                (min.x+max.x)/2,
                (min.y+max.y)/2,
                (min.z+max.z)/2
            )

            modelNode.position = SCNVector3(-center.x,-center.y,-center.z)

            spinNode.addChildNode(modelNode)

            context.coordinator.modelNode = modelNode

            spinNode.eulerAngles = SCNVector3(-Float.pi/30,0,0)

            context.coordinator.originalSpinEulerAngles = spinNode.eulerAngles

            context.coordinator.startIdleSpin()

        } catch {
            print(error)
        }

        // Gestures

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )

        let rotation = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotation(_:))
        )

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )

        pan.delegate = context.coordinator
        rotation.delegate = context.coordinator
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(rotation)
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var parent: FrameModelView

        var spinNode: SCNNode?
        var modelNode: SCNNode?
        var cameraNode: SCNNode?

        var originalSpinEulerAngles = SCNVector3Zero
        var originalCameraPosition = SCNVector3(4,5,370)

        var baseX:Float = 0
        var baseY:Float = 0
        var baseZ:Float = 0

        var pinchStart:Float = 370

        var resetWork:DispatchWorkItem?

        init(_ parent:FrameModelView) {
            self.parent = parent
        }

        func startIdleSpin() {

            guard let node = spinNode else {return}

            node.removeAction(forKey:"spin")

            let spin = SCNAction.rotateBy(
                x:0,
                y:CGFloat.pi*2,
                z:0,
                duration:16
            )

            node.runAction(.repeatForever(spin), forKey:"spin")
        }

        func stopIdleSpin(){
            spinNode?.removeAction(forKey:"spin")
        }

        func beginInteraction(){
            parent.isInteracting = true
            stopIdleSpin()
            resetWork?.cancel()
        }

        func endInteraction(){
            parent.isInteracting = false
            reset()
        }

        func reset(){

            resetWork?.cancel()

            let work = DispatchWorkItem{ [weak self] in

                guard let self else {return}

                SCNTransaction.begin()

                SCNTransaction.animationDuration = 1.2

                self.spinNode?.eulerAngles = self.originalSpinEulerAngles
                self.cameraNode?.position = self.originalCameraPosition

                SCNTransaction.completionBlock = {
                    self.startIdleSpin()
                }

                SCNTransaction.commit()
            }

            resetWork = work

            DispatchQueue.main.asyncAfter(
                deadline:.now()+10,
                execute:work
            )
        }

        @objc func handlePan(_ g:UIPanGestureRecognizer){

            guard let node = spinNode else {return}

            let t = g.translation(in:g.view)

            switch g.state{

            case .began:

                beginInteraction()

                baseX = node.eulerAngles.x
                baseY = node.eulerAngles.y

            case .changed:

                node.eulerAngles.y = baseY + Float(t.x)*0.008
                node.eulerAngles.x = baseX + Float(t.y)*0.008

            case .ended,.cancelled,.failed:

                endInteraction()

            default:break
            }
        }

        @objc func handleRotation(_ g:UIRotationGestureRecognizer){

            guard let node = spinNode else {return}

            switch g.state{

            case .began:

                beginInteraction()

                baseZ = node.eulerAngles.z

            case .changed:

                node.eulerAngles.z = baseZ - Float(g.rotation)

            case .ended,.cancelled,.failed:

                endInteraction()

            default:break
            }
        }

        @objc func handlePinch(_ g:UIPinchGestureRecognizer){

            guard let cam = cameraNode else {return}

            switch g.state{

            case .began:

                beginInteraction()

                pinchStart = cam.position.z

            case .changed:

                cam.position.z = pinchStart / Float(g.scale)

            case .ended,.cancelled,.failed:

                endInteraction()

            default:break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
