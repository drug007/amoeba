import cassowary.amoeba;
import cassowary.wrapper;

int main()
{
	{
		auto solver = cassowarySolver;

		auto xl = solver.addVariable("xl");
		auto xm = solver.addVariable("xm");
		auto xr = solver.addVariable("xr");

		solver.addConstraint("xm*2 == xl+xr");
		solver.addConstraint("xl + 10 <= xr");
		solver.addConstraint("xr <= 100");
		solver.addConstraint("xl >= 0");
		solver.addConstraint("xm >= 12");

		xm.addEdit(AM_MEDIUM);
		assert(xm.hasEdit);

		foreach(i; 0..12)
		{
			printf("suggest to %f: ", i*10.0);
			xm.suggest(i*10.0);
			solver.update;
			// am_dumpsolver(solver);
			printf("\txl: %f,\txm: %f,\txr: %f\n",
					xl.value,
					xm.value,
					xr.value);
		}
	}

	return 0;
}