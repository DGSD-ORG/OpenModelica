// name:     WhenStatement2
// keywords: when
// status:   correct
//
//
//

class WhenStat2
  Real x(start = 1);
  Real y1;
  parameter Real y2 = 5;
  Real y3;
algorithm
  when {x > 2, sample(0, 2), x < 5} then
    y1 := sin(x);
    y3 := 2*x + y1 + y2;
  end when;
equation
  der(x) = 2*x;
  annotation(__OpenModelica_commandLineOptions="-d=-newInst");
end WhenStat2;


// Result:
// class WhenStat2
//   Real x(start = 1.0);
//   Real y1;
//   parameter Real y2 = 5.0;
//   Real y3;
// equation
//   der(x) = 2.0 * x;
// algorithm
//   when {x > 2.0, sample(0.0, 2.0), x < 5.0} then
//     y1 := sin(x);
//     y3 := 2.0 * x + y1 + y2;
//   end when;
// end WhenStat2;
// endResult
