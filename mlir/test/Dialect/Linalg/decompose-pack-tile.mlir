// RUN: mlir-opt -split-input-file -transform-interpreter --canonicalize \
// RUN: -transform-preload-library='transform-library-paths=%p/td/decompose-pack.mlir' \
// RUN: -transform-interpreter=entry-point=decompose_pack \
// RUN: -transform-interpreter  %s | FileCheck %s

func.func @KCRS_to_KCRSsr(%arg0: tensor<1x1x128x64xf32>, %arg1: tensor<1x1x4x8x8x32xf32>) -> tensor<1x1x4x8x8x32xf32> {
  %0 = linalg.pack %arg0 inner_dims_pos = [3, 2] inner_tiles = [8, 32] into %arg1 : tensor<1x1x128x64xf32> -> tensor<1x1x4x8x8x32xf32>
  return %0 : tensor<1x1x4x8x8x32xf32>
}
// CHECK-DAG:   #[[MAP0:.+]] = affine_map<(d0) -> (d0 * 32)>
// CHECK-DAG:   #[[MAP2:.+]] = affine_map<(d0) -> (d0 * 8)>
// CHECK:       func.func @KCRS_to_KCRSsr
// CHECK-SAME:    %[[SRC:[a-zA-Z0-9]+]]
// CHECK-SAME:    %[[DEST:[a-zA-Z0-9]+]]
// CHECK:         scf.for %[[R:[a-zA-Z0-9]+]] =
// CHECK:           scf.for %[[S:[a-zA-Z0-9]+]] {{.*}} iter_args(%[[ITER_SLICE:.*]] =
// CHECK:             %[[IN_R:.+]] = affine.apply #[[MAP0]](%[[R]])
// CHECK:             %[[IN_S:.+]] = affine.apply #[[MAP2]](%[[S]])
// CHECK:             %[[SRC_SLICE:.+]] = tensor.extract_slice %[[SRC]]
// CHECK-SAME:          [0, 0, %[[IN_R]], %[[IN_S]]] [1, 1, 32, 8] [1, 1, 1, 1]
// CHECK:             %[[EMPTY:.*]] = tensor.empty() : tensor<1x1x8x32xf32>
// CHECK:             %[[TRANSP:.*]] = linalg.transpose
// CHECK-SAME:          ins(%[[SRC_SLICE]] : tensor<1x1x32x8xf32>)
// CHECK-SAME:          outs(%[[EMPTY]] : tensor<1x1x8x32xf32>)
// CHECK-SAME:          permutation = [0, 1, 3, 2]
// CHECK:             %{{.+}} = tensor.insert_slice %[[TRANSP]] into %{{.+}}

module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%arg1: !transform.any_op {transform.readonly}) {
      %0 = transform.structured.match ops{["linalg.pack"]} in %arg1 : (!transform.any_op) -> !transform.any_op
      %1, %loops:4 = transform.structured.tile_using_for %0 tile_sizes [1, 1, 1, 1] : (!transform.any_op) -> (!transform.any_op, !transform.any_op, !transform.any_op, !transform.any_op, !transform.any_op)
      transform.yield
  }
}

// -----

func.func @pad_and_pack(%arg0: tensor<13x15xf32>, %arg1: tensor<2x8x8x2xf32>, %arg2: f32) -> tensor<2x8x8x2xf32> {
  %0 = linalg.pack %arg0 padding_value(%arg2 : f32) inner_dims_pos = [0, 1] inner_tiles = [8, 2] into %arg1 : tensor<13x15xf32> -> tensor<2x8x8x2xf32>
  return %0 : tensor<2x8x8x2xf32>
}
// CHECK:       func.func @pad_and_pack
// CHECK-SAME:    %[[SRC:[a-zA-Z0-9]+]]
// CHECK-SAME:    %[[DEST:[a-zA-Z0-9]+]]
// CHECK-SAME:    %[[PAD_VAL:[a-zA-Z0-9]+]]
// CHECK:         scf.for
// CHECK:           scf.for
// CHECK:             %[[SRC_SLICE]] = tensor.extract_slice %[[SRC]]
// CHECK:             %[[PAD:.+]] = tensor.pad %[[SRC_SLICE]]
// CHECK:               tensor.yield %[[PAD_VAL]]
// CHECK:             } : tensor<?x?xf32> to tensor<8x2xf32>
// CHECK-NOT:         linalg.transpose
// CHECK:             %{{.+}} = tensor.insert_slice %[[PAD]] into %{{.+}}

module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%arg1: !transform.any_op {transform.readonly}) {
      %0 = transform.structured.match ops{["linalg.pack"]} in %arg1 : (!transform.any_op) -> !transform.any_op
      %1, %loops:2 = transform.structured.tile_using_for %0 tile_sizes [1, 1] : (!transform.any_op) -> (!transform.any_op, !transform.any_op, !transform.any_op)
      transform.yield
  }
}

// -----


func.func @KC_to_CKkc(%arg0: tensor<128x256xf32>, %arg1: tensor<32x4x32x8xf32>) -> tensor<32x4x32x8xf32> {
  %0 = linalg.pack %arg0 outer_dims_perm = [1, 0] inner_dims_pos = [0, 1] inner_tiles = [32, 8] into %arg1 : tensor<128x256xf32> -> tensor<32x4x32x8xf32>
  return %0 : tensor<32x4x32x8xf32>
}
// CHECK-DAG:   #[[MAP0:.+]] = affine_map<(d0) -> (d0 * 32)>
// CHECK-DAG:   #[[MAP2:.+]] = affine_map<(d0) -> (d0 * 8)>
// CHECK:       func.func @KC_to_CKkc
// CHECK-SAME:    %[[SRC:[a-zA-Z0-9]+]]
// CHECK-SAME:    %[[DEST:[a-zA-Z0-9]+]]
// CHECK:         %{{.+}} = scf.for %[[C:[a-zA-Z0-9]+]] =
// CHECK:           %{{.+}} = scf.for %[[K:[a-zA-Z0-9]+]] =
// CHECK-DAG:         %[[IN_K:.+]] = affine.apply #[[MAP0]](%[[K]])
// CHECK-DAG:         %[[IN_C:.+]] = affine.apply #[[MAP2]](%[[C]])
// CHECK:             %[[TILE:.+]] = tensor.extract_slice %[[SRC]]
// CHECK-SAME:          [%[[IN_K]], %[[IN_C]]] [32, 8] [1, 1]
// CHECK-NOT:         linalg.transpose
// CHECK:             %[[SUB_ITER:.+]] = tensor.insert_slice %[[TILE]] into %{{[a-zA-Z0-9]+}}
// CHECK-SAME:          [0, 0, 0, 0] [1, 1, 32, 8] [1, 1, 1, 1] : tensor<32x8xf32> into tensor<1x1x32x8xf32>
// CHECK:             %{{.+}} = tensor.insert_slice %[[SUB_ITER]] into %{{[a-zA-Z0-9]+}}
// CHECK-SAME:          [%[[C]], %[[K]], 0, 0] [1, 1, 32, 8] [1, 1, 1, 1] : tensor<1x1x32x8xf32> into tensor<32x4x32x8xf32>
module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%arg1: !transform.any_op {transform.readonly}) {
      %0 = transform.structured.match ops{["linalg.pack"]} in %arg1 : (!transform.any_op) -> !transform.any_op
      %1, %loops:2 = transform.structured.tile_using_for %0 tile_sizes [1, 1] : (!transform.any_op) -> (!transform.any_op, !transform.any_op, !transform.any_op)
      transform.yield
  }
}
