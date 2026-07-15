spv.use();

OpCapability Shader
OpMemoryModel Logical GLSL450
OpEntryPoint GLCompute %3 "main"
OpExecutionMode %3 LocalSize 1 1 1
%1 = OpTypeVoid
%2 = OpTypeFunction %1
%3 = OpFunction %1 None %2
%4 = OpLabel
OpReturn
OpFunctionEnd
