function forward(backend::GPUBackend, state::BinaryCrossEntropyLossLayerState, inputs::Vector{Blob})
  pred    = inputs[1]
  label   = inputs[2]
  data_type = eltype(pred)

  num = get_num(pred)
  dim = length(pred)

  x_block = int(ceil(convert(Float64, dim)/CUDA.THREADS_PER_BLOCK_X))

  loss_blob = make_zero_blob(backend, Float32, 1, 1, 1, 1)

  if data_type == Float32
    kernel = get_mocha(backend).binary_cross_entropy_loss_forward_float
  elseif data_type == Float64
    kernel = get_mocha(backend).binary_cross_entropy_loss_forward_double
  else
    error("Unsupported data type $data_type")
  end

  CUDA.launch(kernel, x_block, (CUDA.THREADS_PER_BLOCK_X, 1),
        (get_ptr(pred).p, get_ptr(label).p, dim, get_ptr(loss_blob).p), get_stream(backend))

  loss = Float32[0]
  copy!(loss, loss_blob)
  state.loss = state.layer.weight * loss[1] / num
  destroy(loss_blob)
end

function backward(backend::GPUBackend, state::BinaryCrossEntropyLossLayerState, inputs::Vector{Blob}, diffs::Vector{Blob})
  if !any([isa(d, CuTensorBlob) for d in diffs])
    return
  end

  pred    = inputs[1]
  label   = inputs[2]
  data_type = eltype(pred)

  num = get_num(pred)
  dim = length(pred)

  x_block = int(ceil(convert(Float64, dim)/CUDA.THREADS_PER_BLOCK_X))

  if data_type == Float32
    kernel = get_mocha(backend).binary_cross_entropy_loss_backward_float
  elseif data_type == Float64
    kernel = get_mocha(backend).binary_cross_entropy_loss_backward_double
  else
    error("Unsupported data type $data_type")
  end

  null_ptr = convert(Ptr{data_type}, 0)
  grad_pred =  isa(diffs[1], CuTensorBlob) ? get_ptr(diffs[1]).p : null_ptr
  grad_label = isa(diffs[2], CuTensorBlob) ? get_ptr(diffs[2]).p : null_ptr

  CUDA.launch(kernel, x_block, (CUDA.THREADS_PER_BLOCK_X, 1),
        (get_ptr(pred).p, get_ptr(label).p, dim, grad_pred, grad_label,
         convert(data_type, state.layer.weight/num)))

end
