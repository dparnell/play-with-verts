(in-package #:play-with-verts)

;;------------------------------------------------------------

;; We will use this function as our vertex shader
(defun-g some-vert-stage ((vert g-pnt)
                          &uniform (now :float)
                          (scale :float)
                          (model->world :mat4)
                          (world->view :mat4)
                          (view->clip :mat4))
  (let* (;; Unpack the data from our vert
         ;; (pos & normal are in model space)
         (pos (* (pos vert) scale))
         (normal (norm vert))
         (uv (tex vert))

         ;; model space to world space.
         ;; We don't want to translate the normal, so we
         ;; turn the mat4 to a mat3
         (model-pos (v! pos 1))
         (world-pos (* model->world model-pos))
         (world-norm (* (m4:to-mat3 model->world)
                        normal))

         ;; world space to view space
         (view-pos (* world->view world-pos))

         ;; view space to clip space
         (clip-pos (* view->clip view-pos)))

    ;; return the clip-space position and the 3 other values
    ;; that will be passed to the fragment shader
    (values
     clip-pos
     (s~ world-pos :xyz)
     world-norm
     uv)))

(defun-g terrain-vert-stage ((vert g-pnt)
                             &uniform (now :float)
                             (scale :float)
                             (model->world :mat4)
                             (world->view :mat4)
                             (view->clip :mat4)
                             (height-water-sediment-map :sampler-2d))
  (let* (;; Unpack the data from our vert
         ;; (pos & normal are in model space)
         (pos (* (pos vert) scale))
         (uv (tex vert))

         ;; Unpack data from height-water-sediment-map
         (height (x (texture height-water-sediment-map uv)))
         (pos (+ pos (v! 0 height 0)))

         ;; model space to world space
         (model-pos (v! pos 1))
         (world-pos (* model->world model-pos))

         ;; world space to view space
         (view-pos (* world->view world-pos))

         ;; view space to clip space
         (clip-pos (* view->clip view-pos)))

    (values
     clip-pos
     uv)))

(defun-g terrain-geom-stage ((uvs (:vec2 3))
                             &uniform (height-water-sediment-map :sampler-2d))
  (declare (output-primitive :kind :triangle-strip :max-vertices 6))
  ;;
  ;; re-emit the terrain mesh
  (let ((terrain-pos-0 (gl-position (aref gl-in 0)))
        (terrain-pos-1 (gl-position (aref gl-in 1)))
        (terrain-pos-2 (gl-position (aref gl-in 2)))
        (tex-uv-0 (* (v! 0.5 1) (aref uvs 0)))
        (tex-uv-1 (* (v! 0.5 1) (aref uvs 1)))
        (tex-uv-2 (* (v! 0.5 1) (aref uvs 2))))
    (emit ()
          terrain-pos-0
          tex-uv-0)
    (emit ()
          terrain-pos-1
          tex-uv-1)
    (emit ()
          terrain-pos-2
          tex-uv-2)
    (end-primitive)
    ;;
    ;; emit the water mesh
    (let* ((hws (texture height-water-sediment-map (aref uvs 0)))
           (water-height (y hws)))
      (emit ()
            (+ terrain-pos-0 (v! 0 (- water-height 0.001) 0 0))
            (+ (v! 0.5 0) tex-uv-0)))

    (let* ((hws (texture height-water-sediment-map (aref uvs 1)))
           (water-height (y hws)))
      (emit ()
            (+ terrain-pos-1 (v! 0 (- water-height 0.001) 0 0))
            (+ (v! 0.5 0) tex-uv-1)))

    (let* ((hws (texture height-water-sediment-map (aref uvs 2)))
           (water-height (y hws)))
      (emit ()
            (+ terrain-pos-2 (v! 0 (- water-height 0.001) 0 0))
            (+ (v! 0.5 0) tex-uv-2)))
    (end-primitive)
    ;;
    (values)))

(defun-g terrain-frag-stage ((uv :vec2)
                             &uniform
                             (albedo :sampler-2d)
                             (height-water-sediment-map :sampler-2d))
  (let* ((object-color (texture albedo uv))
         (ambient 0.4))
    (* object-color ambient)))

;; We will use this function as our fragment shader
(defun-g some-frag-stage ((frag-pos :vec3)
                          (frag-normal :vec3)
                          (uv :vec2)
                          &uniform (light-pos :vec3)
                          (cam-pos :vec3)
                          (albedo :sampler-2d)
                          (spec-map :sampler-2d))
  (let* (;; we will multiply with color with the light-amount
         ;; to get our final color
         (object-color (texture albedo uv))

         ;; We need to normalize the normal because the linear
         ;; interpolation from the vertex shader will have shortened it
         (frag-normal (normalize frag-normal))

         ;; ambient color is the same from all directions
         (ambient 0.2)

         ;; diffuse color is the cosine of the angle between the light
         ;; and the normal. As both the vectors are normalized we can
         ;; use the dot-product to get this.
         (vec-to-light (- light-pos frag-pos))
         (dir-to-light (normalize vec-to-light))
         (diffuse (saturate (dot dir-to-light frag-normal)))

         ;; The specular is similar but we do it between the direction
         ;; our camera is looking and the direction the light will reflect.
         ;; We also raise it to a big power so it's a much smaller spot
         ;; with a quick falloff
         (vec-to-cam (- cam-pos frag-pos))
         (dir-to-cam (normalize vec-to-cam))
         (reflection (normalize (reflect (- dir-to-light) frag-normal)))
         (specular-power (* 4 (x (texture spec-map uv))))
         (specular (* (expt (saturate (dot reflection dir-to-cam))
                            32f0)
                      specular-power))

         ;; The final light amount is the sum of the different components
         (light-amount (+ ambient
                          diffuse
                          ;;specular
                          )))

    ;; And we multipy with the object color. This means that 0 light results
    ;; in no color, and 1 light results in full color. Cool!
    (* object-color light-amount)))

;; The pipeline itself, we map-g over this to draw stuff
(defpipeline-g some-pipeline ()
  (some-vert-stage g-pnt)
  (some-frag-stage :vec3 :vec3 :vec2))

(defpipeline-g terrain-pipeline ()
  :vertex (terrain-vert-stage g-pnt)
  :geometry (terrain-geom-stage (:vec2 3))
  :fragment (terrain-frag-stage :vec2))

;;------------------------------------------------------------

(defun upload-uniforms-for-cam (camera)
  (map-g #'some-pipeline nil
         :light-pos *light-pos*
         :cam-pos (pos camera)
         :now (now)
         :world->view (get-world->view-space camera)
         :view->clip (rtg-math.projection:perspective
                      (x (viewport-resolution (current-viewport)))
                      (y (viewport-resolution (current-viewport)))
                      0.1
                      800f0
                      60f0))
  (map-g #'terrain-pipeline nil
         :now (now)
         :world->view (get-world->view-space camera)
         :view->clip (rtg-math.projection:perspective
                      (x (viewport-resolution (current-viewport)))
                      (y (viewport-resolution (current-viewport)))
                      0.1
                      800f0
                      60f0)))

;;------------------------------------------------------------
