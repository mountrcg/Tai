# Extract the unmodified numeric methods; compile the output with kotlinc, then run the jar.
import sys
from pathlib import Path
s=(Path(sys.argv[1]) / 'plugins/smoothing/src/commonMain/kotlin/app/aaps/plugins/smoothing/UnscentedKalmanFilterPlugin.kt').read_text()
def method(name):
 start=s.index('    private fun '+name+'('); opening=s.index('{',start); depth=1;i=opening+1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]
const=s[s.index('    private val n ='):s.index('    /**',s.index('    private fun rateDamp'))]
state=s[s.index('    private var learnedR'):s.index('    // Event system.')]
methods='\n'.join(method(n) for n in ['findDataSegments','smoothInternal','processSegment','trackInnovation','adaptMeasurementNoise','computeTrendArrow','computeSmootherGain','predict','update','generateSigmaPoints','matrixSqrt2x2','copyRawToSmoothed'])
init='''init { wm[0] = lambda / (n + lambda); wc[0] = wm[0] + (1 - alpha * alpha + beta); for(i in 1 until 2*n+1) {wm[i]=1/(2*(n+lambda)); wc[i]=wm[i]} }
fun smooth(data: MutableList<InMemoryGlucoseValue>) = smoothInternal(data, true)
private fun shouldResetLearning(t:Long) = false
private fun resetLearning() {}
private fun savePersistedParameters() {}
'''
pre='''import kotlin.math.*
class InMemoryGlucoseValue(val timestamp:Long,val value:Double) {val calibratedOrValue get()=value;var smoothed=0.0;var trendArrow=TrendArrow.NONE}
enum class TrendArrow { NONE, FLAT, DOUBLE_UP, SINGLE_UP, FORTY_FIVE_UP, DOUBLE_DOWN, SINGLE_DOWN, FORTY_FIVE_DOWN }
object LTag {val GLUCOSE=0}
object aapsLogger {fun debug(vararg x:Any?) {};fun info(vararg x:Any?) {};fun warn(vararg x:Any?) {}}
private fun Double.fmt(n:Int)=toString()
class Reference {
private data class DataSegment(val startIdx:Int,val endIdx:Int)
private data class FilterState(val x:DoubleArray,val p:DoubleArray,val xPred:DoubleArray,val pPred:DoubleArray,val dt:Double)
'''
tail=s[s.index('private const val DENSE_CADENCE_MAX_MINUTES'):]
main='''
fun main() {
 val data=(0 until 60).map {i -> InMemoryGlucoseValue(1700000000000L-i*60000L,120.0+(if(i%2==0) 3.0 else -3.0)+i*0.2)}.toMutableList()
 println(Reference().smooth(data).joinToString(",", "[", "]") {it.smoothed.toString()})
}
'''
Path(sys.argv[2]).write_text(pre+const+state+init+methods+'\n}\n'+tail+main)
