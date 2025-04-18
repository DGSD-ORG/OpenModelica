// name: Tuple1
// status: correct

function f
  input Real x;
  output Real y = x;
  output Real z = x;
end f;

model Tuple1
  Real x;
equation
  x = f(time);
  annotation(__OpenModelica_commandLineOptions="-d=newInst -f");
end Tuple1;

// Result:
// //! base 0.1.0
// package 'Tuple1'
//   function 'f'
//     input Real 'x';
//     output Real 'y' = 'x';
//     output Real 'z' = 'x';
//   end 'f';
//
//   model 'Tuple1'
//     Real 'x';
//   equation
//     'x' = 'f'(time);
//   end 'Tuple1';
// end 'Tuple1';
// endResult
