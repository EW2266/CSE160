/**
 * MapList
 * This component provides a MapList with an array of buckets (t @integer(), List<s @integer()>).
 * Types t and s should be integers. Size is constrained to the upper bound of uint16_t
 *
 * @author Chris DeSoto
 * @date   2018/09/10
 *
 */
interface MapList<t, s> {
   command void insertVal(t key, s val);
   command void removeVal(t key, s val);
   command bool containsList(t key);
   command bool containsVal(t key, s val);
   command bool isEmpty();
   command bool listIsEmpty(t key);
   command void printList(t key);
}
